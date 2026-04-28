class Photo < ActiveRecord::Base
  belongs_to :user
  belongs_to :photo, polymorphic: true
  has_attached_file :image,
    source_file_options: { all: "-auto-orient"},
    styles: {
      icon: "32x32#",
      thumb: "150x150#",
      one_by_one: "500x500#",
      sixteen_by_nine: "500x281#",
      four_by_three: "500x375#",
      large: "1000x1000#",
      original: ""
    }
  #  default_url: ":rails_root/public/:style/missing.png",
  #  path: ":rails_root/public/system/:class/:attachment/:id_partition/:style/:filename"

  validates_attachment_content_type :image, content_type: /\Aimage\/.*\Z/

  enum image_type: [
    :basic,
    :banner,
    :icon]

  scope :photos_taken, ->(user) { where(user: user).count }
  def to_param
    "#{id}-#{name.parameterize}"
  end
end
