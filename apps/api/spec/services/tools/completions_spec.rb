require "rails_helper"

# `completion/complete` is the dropdown a client shows while somebody
# fills in a prompt argument.
#
# It matters more here than it would elsewhere: every write path in this
# system takes a slug, and slugs are the one thing nobody can guess —
# `search_taxonomy` exists because a model cannot turn "garbanzo" into
# `chickpea`. A person picking "Scan a menu into the database" out of a
# prompt list has the same problem and, until this shipped, a blank box.
RSpec.describe Tools::Completions do
  let!(:city) { create(:city, slug: "durango") }

  def values(name, value)
    described_class.call(argument_name: name, value: value).dig(:completion, :values)
  end

  describe "restaurants" do
    let!(:ninis)  { create(:restaurant, :published, city: city, slug: "ninis-taqueria") }
    let!(:nickel) { create(:restaurant, :published, city: city, slug: "nickel-cafe") }

    it "completes a partial slug" do
      expect(values(:restaurant, "ni")).to contain_exactly("nickel-cafe", "ninis-taqueria")
    end

    it "narrows as more is typed" do
      expect(values(:restaurant, "nin")).to eq(["ninis-taqueria"])
    end

    # Prefix, not substring. A slug is a name someone is part-way through
    # typing; matching the middle turns "cafe" into every restaurant that
    # happens to contain the word.
    it "matches the start of a slug rather than anywhere in it" do
      expect(values(:restaurant, "cafe")).to be_empty
    end

    # The one place this could leak. Completions run before any tool call
    # and carry no scope of their own, so an unpublished restaurant
    # appearing here would announce a draft to anyone who typed two
    # letters.
    it "never suggests an unpublished restaurant" do
      create(:restaurant, city: city, slug: "nine-secret-supper")

      expect(values(:restaurant, "ni")).not_to include("nine-secret-supper")
    end

    it "offers everything published when nothing is typed yet" do
      expect(values(:restaurant, "")).to contain_exactly("nickel-cafe", "ninis-taqueria")
    end
  end

  describe "taxonomy" do
    let!(:chickpea) { create(:ingredient, slug: "chickpea", path: "legume.chickpea") }
    let!(:cheddar)  { create(:ingredient, slug: "dairy-cheddar", path: "dairy.cheddar") }
    let!(:tag)      { create(:tag, slug: "dairy-free", family: "diet") }

    # One box, both taxonomies — a person avoiding "dairy" does not know
    # or care whether the thing they mean is an ingredient or a tag.
    it "completes across ingredients and tags together" do
      expect(values(:avoid, "dairy")).to contain_exactly("dairy-cheddar", "dairy-free")
    end

    it "completes a city" do
      expect(values(:city, "dur")).to eq(["durango"])
    end
  end

  describe "input that is not a prefix" do
    let!(:ninis) { create(:restaurant, :published, city: city, slug: "ninis-taqueria") }

    # `%` and `_` are characters someone typed, not a pattern they meant.
    # Unsanitized, "%" would match every restaurant in the database.
    it "treats LIKE metacharacters as literal" do
      expect(values(:restaurant, "%")).to be_empty
      expect(values(:restaurant, "_inis-taqueria")).to be_empty
    end

    it "answers an argument it does not know with an empty list, not an error" do
      expect(values(:not_an_argument, "x")).to eq([])
    end
  end

  describe "hasMore" do
    it "is false when everything fits" do
      create(:restaurant, :published, city: city, slug: "one")

      expect(described_class.call(argument_name: :restaurant, value: "").dig(:completion, :hasMore))
        .to be(false)
    end

    # An honest `hasMore` is what makes a client say "keep typing" instead
    # of implying the list is the whole answer.
    it "is true when the list was capped" do
      (described_class::LIMIT + 1).times { |i| create(:restaurant, :published, city: city, slug: "r#{i}") }

      result = described_class.call(argument_name: :restaurant, value: "r")
      expect(result.dig(:completion, :values).size).to eq(described_class::LIMIT)
      expect(result.dig(:completion, :hasMore)).to be(true)
    end

    # `avoid` merges two taxonomies, so it is the one resolver that can
    # trim the overflow row before `call` ever sees it — and then reports
    # "that's all of them" over a taxonomy with tens of thousands of
    # nodes, which is the answer most likely to be capped and the one a
    # person most needs to know is partial.
    it "is true for the merged taxonomy list too" do
      (described_class::LIMIT + 1).times { |i| create(:ingredient, slug: "z#{i}", path: "z.n#{i}") }

      result = described_class.call(argument_name: :avoid, value: "z")
      expect(result.dig(:completion, :values).size).to eq(described_class::LIMIT)
      expect(result.dig(:completion, :hasMore)).to be(true)
    end
  end

  # The drift guard. A workflow can declare an argument, get a box drawn
  # for it by every client, and have nothing here able to fill it — which
  # looks to a person exactly like a broken feature rather than a missing
  # one.
  it "knows how to complete every argument any workflow declares" do
    declared = Tools::Topology::WORKFLOWS.flat_map { |flow| Array(flow[:arguments]) }.uniq

    expect(declared).to be_present
    expect(declared.reject { |name| described_class.known?(name) }).to be_empty
  end

  it "describes every argument it knows, so a client can label the box" do
    expect(described_class::ARGUMENTS.keys.reject { |name| described_class.describe(name).present? })
      .to be_empty
  end
end
