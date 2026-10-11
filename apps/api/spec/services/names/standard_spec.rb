require "rails_helper"

# The BiteWorthy naming standard. Menus and PDFs print dish names in
# capitals for emphasis; read back on a phone they shout. A name that is
# mostly capitals becomes Title Case and a description becomes sentence
# case, while text someone cased on purpose ("McDonald's", "iPhone") is
# left exactly as written.
RSpec.describe Names::Standard do
  describe ".item_name" do
    {
      "CHICKEN TIKKA MASALA"     => "Chicken Tikka Masala",
      "MAC AND CHEESE W/ BACON"  => "Mac and Cheese w/ Bacon",
      "THE CLASSIC"              => "The Classic",
      "NY STRIP"                 => "NY Strip",
      "BBQ PULLED PORK"          => "BBQ Pulled Pork",
      "PB&J SANDWICH"            => "PB&J Sandwich",
      "JALAPEÑO POPPERS"         => "Jalapeño Poppers",
      "SHEPHERD'S PIE"           => "Shepherd's Pie",
      "PAN-SEARED SALMON"        => "Pan-Seared Salmon",
      "SALT-AND-PEPPER WINGS"    => "Salt-and-Pepper Wings",
      "BBQ-STYLE RIBS"           => "BBQ-Style Ribs",
      "BLT W/BACON"              => "BLT w/Bacon",
      "1/2 RACK RIBS"            => "1/2 Rack Ribs",
      "USDA PRIME RIBEYE"        => "USDA Prime Ribeye",
      "12OZ RIBEYE"              => "12oz Ribeye",
      "\"THE BOSS\" BURGER"      => "\"The Boss\" Burger",
      "ARROZ Y FRIJOLES"         => "Arroz y Frijoles"
    }.each do |shouted, standard|
      it "title-cases #{shouted.inspect}" do
        expect(described_class.item_name(shouted)).to eq(standard)
      end
    end

    it "leaves deliberate mixed case alone" do
      expect(described_class.item_name("McDonald's Style Burger")).to eq("McDonald's Style Burger")
      expect(described_class.item_name("BBQ Pulled Pork")).to eq("BBQ Pulled Pork")
      expect(described_class.item_name("iPhone Special")).to eq("iPhone Special")
    end

    it "leaves short all-caps names alone, because they are usually acronyms" do
      expect(described_class.item_name("BLT")).to eq("BLT")
      expect(described_class.item_name("KFC")).to eq("KFC")
    end

    # A trailing or leading asterisk is a footnote marker (usually the
    # raw/undercooked advisory), not part of the dish's name.
    it "strips footnote asterisks from either end" do
      expect(described_class.item_name("Tuna Tartare*")).to eq("Tuna Tartare")
      expect(described_class.item_name("STEAK TARTARE **")).to eq("Steak Tartare")
      expect(described_class.item_name("*Oysters on the Half Shell")).to eq("Oysters on the Half Shell")
    end

    it "never blanks a name made only of asterisks" do
      expect(described_class.item_name("***")).to eq("***")
    end

    it "is idempotent" do
      once = described_class.item_name("MAC AND CHEESE W/ BACON*")
      expect(described_class.item_name(once)).to eq(once)
    end

    it "passes nil through" do
      expect(described_class.item_name(nil)).to be_nil
    end
  end

  describe ".description" do
    it "sentence-cases a shouting description, keeping acronyms" do
      expect(described_class.description("SLOW-SMOKED BRISKET WITH HOUSE BBQ SAUCE. SERVED WITH FRIES! GF ON REQUEST"))
        .to eq("Slow-smoked brisket with house BBQ sauce. Served with fries! GF on request")
    end

    it "leaves a normally cased description alone" do
      text = "Grilled steak, cilantro, onion, lime. Ask about our GF tortillas."
      expect(described_class.description(text)).to eq(text)
    end

    # Descriptions keep their asterisks: "*Consuming raw or undercooked…"
    # is the advisory itself, not a marker pointing at it.
    it "does not strip asterisks" do
      expect(described_class.description("*Contains raw egg")).to eq("*Contains raw egg")
    end

    it "passes nil and blank through" do
      expect(described_class.description(nil)).to be_nil
      expect(described_class.description("")).to eq("")
    end
  end
end
