# frozen_string_literal: true

# Sixteen leaf cuisines so Jev has somewhere to put a dish. The 2026-10-10
# retag_cuisine dry runs showed it refusing Haiku's force-fits (momo as
# indian) with nothing to offer instead, because the family had seven
# leaves.
#
# Production seeds only on FIRST boot (`db:prepare` in deploy.yml), so the
# same rows in `db/seeds/tags.yml` never reach live on their own. This
# upserts them as a one-time data change, idempotent. A database with no
# `cuisine` root has never been seeded (a fresh dev or test database): it
# gets nothing here rather than orphans, and the seed brings the leaves.
class UpsertCuisineLeafTags < ActiveRecord::Migration[8.1]
  # Migration-local class to avoid coupling to app/models.
  class MigrationTag < ActiveRecord::Base
    self.table_name = "tags"
  end

  TAGS = [
    { slug: "nepali-tibetan", name: "Nepali & Tibetan", path: "cuisine.nepali_tibetan" },
    { slug: "mediterranean",  name: "Mediterranean",    path: "cuisine.mediterranean" },
    { slug: "greek",          name: "Greek",            path: "cuisine.greek" },
    { slug: "middle-eastern", name: "Middle Eastern",   path: "cuisine.middle_eastern" },
    { slug: "latin-american", name: "Latin American",   path: "cuisine.latin_american" },
    { slug: "caribbean",      name: "Caribbean",        path: "cuisine.caribbean" },
    { slug: "korean",         name: "Korean",           path: "cuisine.korean" },
    { slug: "vietnamese",     name: "Vietnamese",       path: "cuisine.vietnamese" },
    { slug: "french",         name: "French",           path: "cuisine.french" },
    { slug: "spanish",        name: "Spanish",          path: "cuisine.spanish" },
    { slug: "german",         name: "German",           path: "cuisine.german" },
    { slug: "ethiopian",      name: "Ethiopian",        path: "cuisine.ethiopian" },
    { slug: "southern",       name: "Southern",         path: "cuisine.southern" },
    { slug: "cajun-creole",   name: "Cajun & Creole",   path: "cuisine.cajun_creole" },
    { slug: "bbq",            name: "Barbecue",         path: "cuisine.bbq" },
    { slug: "tex-mex",        name: "Tex-Mex",          path: "cuisine.tex_mex" }
  ].map { |row| row.merge(family: "cuisine") }.freeze

  def up
    unless MigrationTag.exists?(path: "cuisine")
      puts "No cuisine root tag: taxonomy not seeded yet, leaving the leaves to db/seeds"
      return
    end

    TAGS.each do |attrs|
      tag = MigrationTag.find_or_initialize_by(slug: attrs[:slug])
      # A slug that already exists elsewhere in the tree is a different
      # tag wearing this name; moving it would re-parent its item rows.
      if tag.persisted? && [ tag.path.to_s, tag.family ] != [ attrs[:path], attrs[:family] ]
        raise "tag #{attrs[:slug]} exists at #{tag.family}/#{tag.path}, not #{attrs[:family]}/#{attrs[:path]}"
      end

      tag.assign_attributes(attrs)
      tag.save!
    end

    puts "Upserted #{TAGS.size} cuisine leaf tags"
  end

  def down
    # Non-destructive: a leaf may already carry item_tags rows.
    puts "Skipped cuisine tag removal (non-destructive)"
  end
end
