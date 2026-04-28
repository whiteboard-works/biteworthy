# Upload files to Amazon S3
Paperclip::Attachment.default_options.update(
  storage: :s3,
  url: ':s3_domain_url',
  path: "/#{Rails.env}/photos/:attachment/:id_partition/:style/:filename",
  s3_credentials: {
    bucket: 'biteworthy',
    access_key_id: ENV['AWS_ACCESS_KEY_ID'],
    secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
    s3_region: ENV['AWS_REGION'],
  }
)
