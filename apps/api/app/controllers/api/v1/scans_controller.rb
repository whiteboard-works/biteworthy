module Api
  module V1
    # Menu scans without the chat.
    #
    # The chat reaches the same three tools, but there every "is it done
    # yet?" is a full model round, and a slow extraction can exhaust the
    # turn's iteration budget on polling alone. A scan screen only needs a
    # row read, so this is the REST door over the same tools — auth,
    # quotas and publishing rules stay in the tool, where both doors share
    # them.
    class ScansController < BaseController
      # A tool reports failure as a code in its payload rather than raising;
      # these are the ones a client should branch on by status.
      ERROR_STATUS = {
        "unauthorized"         => :unauthorized,
        "forbidden"            => :forbidden,
        "forbidden_restaurant" => :forbidden,
        "not_found"            => :not_found,
        "quota_exceeded"       => :too_many_requests,
        "cost_ceiling_reached" => :too_many_requests,
        "tool_failed"          => :internal_server_error
      }.freeze

      def create
        respond_with_tool(
          Tools::Ingestion::StartMenuScan,
          { restaurant:     params.require(:restaurant),
            source_url:     params[:source_url].presence,
            source_text:    params[:source_text].presence,
            attachment_ids: params[:attachment_ids].presence&.then { |ids| Array(ids).map(&:to_s) } }.compact,
          status: :created
        )
      end

      def show
        result = call_tool(Tools::Ingestion::GetScanStatus, scan_id: params[:id])
        return render_tool_error(result) if result[:isError]

        scan = result[:structuredContent]
        scan = scan.merge(dishes: dishes_for(params[:id])) if scan[:ready]
        render json: scan
      end

      # A person pressing "Accept" on the review screen is the confirmation
      # the tool's description asks the chat to obtain first.
      def accept
        args = { scan_id: params[:id] }
        if params[:all].to_s == "true"
          args[:all] = true
        else
          args[:item_ids] = Array(params[:item_ids]).map(&:to_s)
        end
        respond_with_tool(Tools::Ingestion::AcceptStagedItems, args)
      end

      private

      def respond_with_tool(tool, args, status: :ok)
        result = call_tool(tool, **args)
        return render_tool_error(result) if result[:isError]

        render json: result[:structuredContent], status: status
      end

      def call_tool(tool, **args)
        tool.call(
          server_context: { user_id: current_user.id, public_host: public_host, request_id: request.request_id },
          **args
        ).to_h
      end

      def render_tool_error(result)
        payload = result[:structuredContent] || {}
        render json: { error: payload[:message], code: payload[:error] },
               status: ERROR_STATUS.fetch(payload[:error].to_s, :unprocessable_entity)
      end

      # Not `list_staged_items`: that fences every name in
      # <untrusted-content> tags for a model to read, and a person reading a
      # review screen needs the plain text. React escapes it on render.
      # The run was already authorized by the status call above.
      def dishes_for(scan_id)
        items = IngestionItem.where(ingestion_run_id: scan_id).order(:position, :created_at).to_a
        slugs = items.flat_map { |i| ::Ingestion::AssociationPayload.load_all(i.ingredients_payload).map(&:slug) }
        names = Ingredient.where(slug: slugs.uniq).pluck(:slug, :name).to_h

        items.map do |item|
          ingredients = ::Ingestion::AssociationPayload.load_all(item.ingredients_payload)
          {
            id:          item.id,
            name:        item.name,
            description: item.description,
            section:     item.section_name,
            decision:    item.decision,
            price_cents: Array(item.prices_payload).first&.dig("price_cents"),
            ingredients: ingredients.map { |row| names[row.slug] || row.slug },
            needs_attention: Array(item.unresolved_ingredients).any? || ingredients.empty?
          }
        end
      end
    end
  end
end
