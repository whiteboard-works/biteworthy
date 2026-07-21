# Phase 2.4 — second stage of the AI ingestion pipeline.
#
# Triggered automatically when an IngestionRun transitions into
# `:resolving` (see JOB_FOR in IngestionRun). Walks every item in
# `run.staging["sections"][*]["items"]`, asks Anthropic to map them
# onto ingredient slugs from the curated catalog, writes the resolved
# + unresolved arrays back into staging.
#
# On success, fires ResolveTagsJob (which finishes the resolve work and
# transitions the run into `:staged`). The load → resolve → record
# skeleton lives in ResolveStageJob.
class ResolveIngredientsJob < ResolveStageJob
  def stage        = "resolve_ingredients"
  def prompt       = Ingestion::ResolveIngredientsPrompt
  def catalog_text = Ingestion::CatalogBuilder.ingredients_text

  def apply_and_advance(run, result, elapsed_ms)
    apply_resolution_to_items!(
      run, result,
      resolved_col:   :ingredients_payload,
      unresolved_col: :unresolved_ingredients
    )
    run.update!(latency_ms: elapsed_ms)
    ResolveTagsJob.perform_later(run.id)
  end
end
