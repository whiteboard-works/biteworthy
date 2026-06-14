module Api
  module V1
    # POST /api/v1/dmca_notices — legal remediation E10.
    #
    # Public + unauthenticated: a copyright holder (who, by definition,
    # isn't a BiteWorthy user) files a takedown notice from /dmca. The
    # notice is stored for admin review (the repeat-infringer process)
    # and backs the ToS § Copyright clause + the §512 safe harbor.
    #
    # 201 on a valid notice; 422 when a required field or one of the two
    # sworn statements is missing.
    class DmcaNoticesController < BaseController
      skip_before_action :authenticate_user!, only: [:create]

      def create
        notice = DmcaNotice.new(notice_params)
        if notice.save
          render json: { ok: true, id: notice.id }, status: :created
        else
          render json: { ok: false, errors: notice.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      private

      def notice_params
        params.require(:dmca_notice).permit(
          :complainant_name, :complainant_email, :infringing_url,
          :work_description, :good_faith, :accuracy_sworn, :signature
        )
      end
    end
  end
end
