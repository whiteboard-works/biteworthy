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
        sources = { source_url:     params[:source_url].presence,
                    source_text:    params[:source_text].presence,
                    attachment_ids: params[:attachment_ids].presence&.then { |ids| Array(ids).map(&:to_s) } }.compact
        # StartRun would quietly pick one and drop the rest, scanning
        # something other than what the person thinks they sent.
        return render_bad_request("Send one source: a URL, pasted text, or attachments.") if sources.size > 1

        respond_with_tool(
          Tools::Ingestion::StartMenuScan,
          { restaurant: params.require(:restaurant), **sources },
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
        all      = params[:all].to_s == "true"
        item_ids = Array(params[:item_ids]).map(&:to_s).reject(&:blank?)
        # Both at once is ambiguous, and the tool would read it as "all" —
        # publishing dishes the person had deliberately left unticked.
        return render_bad_request("Send either all: true or item_ids, not both.") if all && item_ids.any?

        args = all ? { all: true } : { item_ids: item_ids }
        respond_with_tool(Tools::Ingestion::AcceptStagedItems, { scan_id: params[:id], **args })
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

      def render_bad_request(message)
        render json: { error: message, code: "invalid_argument" }, status: :unprocessable_entity
      end

      def render_tool_error(result)
        payload = result[:structuredContent] || {}
        render json: { error: payload[:message], code: payload[:error] },
               status: ERROR_STATUS.fetch(payload[:error].to_s, :unprocessable_entity)
      end

      # Not `list_staged_items`: that fences every name in
      # <untrusted-content> tags for a model to read, and a person reading a
      # review screen needs the plain text. React escapes it on render.
      # Same facts otherwise — above all `updates_existing_item`, because
      # accepting that dish EDITS a live one rather than adding it.
      # The run was already authorized by the status call above.
      def dishes_for(scan_id)
        items = IngestionItem.where(ingestion_run_id: scan_id)
                             .includes(matched_item: %i[item_variants ingredients tags])
                             .order(:position, :created_at).to_a
        names = taxonomy_names(items)

        items.map do |item|
          ingredients = ::Ingestion::AssociationPayload.load_all(item.ingredients_payload)
          unresolved  = { ingredients: Array(item.unresolved_ingredients), tags: Array(item.unresolved_tags) }
          {
            id:          item.id,
            name:        item.name,
            description: item.description,
            section:     item.section_name,
            decision:    item.decision,
            prices:      ::Ingestion::ItemUpdateDiff.normalize_prices(item.prices_payload),
            ingredients: ingredients.map { |row| names[:ingredients][row.slug] || row.slug },
            tags:        ::Ingestion::AssociationPayload.load_all(item.tags_payload)
                                                        .map { |row| names[:tags][row.slug] || row.slug },
            unresolved:  unresolved,
            # Same rule as IngestionItem.needing_attention.
            needs_attention: unresolved.values.any?(&:any?) || ingredients.empty?,
            updates_existing_item: existing_item_row(item)
          }
        end
      end

      def taxonomy_names(items)
        slugs = ->(attr) { items.flat_map { |i| ::Ingestion::AssociationPayload.load_all(i.public_send(attr)).map(&:slug) }.uniq }
        {
          ingredients: Ingredient.where(slug: slugs.call(:ingredients_payload)).pluck(:slug, :name).to_h,
          tags:        Tag.where(slug: slugs.call(:tags_payload)).pluck(:slug, :name).to_h
        }
      end

      def existing_item_row(item)
        target = item.matched_item
        return nil if target.nil?

        diff = ::Ingestion::ItemUpdateDiff.call(item, target)
        { item_id: target.id, name: target.name, no_changes: diff[:no_changes], diff: diff.except(:no_changes) }
      end
    end
  end
end
