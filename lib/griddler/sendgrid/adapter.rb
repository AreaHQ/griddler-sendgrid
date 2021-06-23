module Griddler
  module Sendgrid
    class Adapter
      def initialize(params)
        @params = params
      end

      def self.normalize_params(params)
        adapter = new(params)
        adapter.normalize_params
      end

      def normalize_params
        params.merge(
          to: recipients(:to).map(&:format),
          cc: recipients(:cc).map(&:format),
          bcc: get_bcc,
          attachments: attachment_files,
          charsets: charsets,
          spam_report: {
            report: params[:spam_report],
            score: params[:spam_score],
          }

        )
      end

      private

      attr_reader :params

      # Sendgrid was sending us malformed emails, so if the first attempt fails 
      # fallback to pulling out the raw email with regex.
      def recipients(key)
        encoded = Mail::Encodings.address_encode(params[key] || '')
        Mail::AddressList.new(encoded).addresses
      rescue ArgumentError
        []
      rescue Mail::Field::IncompleteParseError
        Mail::AddressList.new((params[key] || '').match(/\<(.*)\>/)&.captures&.first).addresses
      end

      def get_bcc
        if bcc = bcc_from_envelope
          bcc - recipients(:to).map(&:address) - recipients(:cc).map(&:address)
        else
          []
        end
      end

      def bcc_from_envelope
        JSON.parse(params[:envelope])["to"] if params[:envelope].present?
      end

      def charsets
        return {} unless params[:charsets].present?
        JSON.parse(params[:charsets]).symbolize_keys
      rescue JSON::ParserError
        {}
      end


      def attachment_files
        attachment_count.times.map do |index|
          extract_file_at(index)
        end
      end

      def attachment_count
        params[:attachments].to_i
      end

      def extract_file_at(index)
        filename = attachment_filename(index)
        content_id = attachment_content_id(index)
        params.delete("attachment#{index + 1}".to_sym).tap do |file|
          if filename.present?
            file.original_filename = filename
          end

          if content_id.present?
            file.headers += "\r\nContent-ID: \"#{content_id}\""
          end
        end
      end

      def attachment_filename(index)
        attachment_info.fetch("attachment#{index + 1}", {})["filename"]
      end

      def attachment_content_id(index)
        attachment_info.fetch("attachment#{index + 1}", {})["content-id"]
      end

      def attachment_info
        @attachment_info ||= JSON.parse(params.delete("attachment-info") || "{}")
      end
    end
  end
end
