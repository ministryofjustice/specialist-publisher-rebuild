require "gds_api/asset_manager"

class Attachment < Document
  attr_accessor :title, :file, :content_type, :url, :content_id, :created_at, :updated_at, :being_updated

  def self.all_from_publishing_api(payload)
    return [] unless payload.fetch('details', {}).key?('attachments')
    payload['details']['attachments'].map { |attachment| Attachment.new(attachment) }
  end

  def initialize(params = {})
    params = params.symbolize_keys
    @file = params[:file]
    @content_type = params[:content_type]
    @url = params[:url]
    @title = extract_title(params)
    @content_id = params[:content_id] || SecureRandom.uuid
    @created_at = params[:created_at]
    @updated_at = params[:updated_at]
    @params = params
    @being_updated = false
  end

  def update_attributes(new_params)
    new_params.each do |k, v|
      self.public_send(:"#{k}=", v)
    end
  end

  def extract_title(params)
    if params[:title].blank?
      if params[:url]
        remove_extension_from_filename(filename)
      elsif params[:file]
        remove_extension_from_filename(params[:file].original_filename)
      end
    else
      params[:title]
    end
  end

  def upload
    response = Services.asset_api.create_asset(file: @file)
    @url = response.file_url
    true
  rescue GdsApi::BaseError => e
    Airbrake.notify(e)
    false
  end

  def update
    response = Services.asset_api.update_asset(id_from_url, file: @file)
    @url = response.file_url
    true
  rescue GdsApi::BaseError => e
    Airbrake.notify(e)
    false
  end

  def id_from_url
    url_array = @url.split('/')
    url_array[url_array.length - 2]
  end

  def remove_extension_from_filename(filename)
    filename.split('.').first
  end

  def destroy
    Services.asset_api.delete_asset(id_from_url)
  rescue GdsApi::BaseError => e
    Airbrake.notify(e)
    false
  end

  def filename
    url.split('/').last
  end

  def snippet
    if url
      "[InlineAttachment:#{filename}]"
    else
      "[InlineAttachment:#{content_id}]"
    end
  end
end
