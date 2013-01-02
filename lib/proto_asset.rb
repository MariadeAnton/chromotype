# This class tries to find the best matching asset,
# or create a new one if this asset hasn't been imported yet
class ProtoAsset

  # "URNers" take a URL and extract a URN
  # which can be used to match the asset with a duplicate file.
  DEFAULT_URNERS = [URN::FsAttrs, URN::Sha1, URN::Exif] # in order of expense

  # "Visitors" are sent #visit_asset when assets are imported.
  DEFAULT_VISITORS = [CameraTag, DateTag, DirTag, FaceTag, GeoTag, SeasonTag, ImageResizer]

  include ExifMixin
  include AttrMemoizer

  attr_memoizer :url, :pathname, :paths, :urns, :asset

  def initialize(url, urners = DEFAULT_URNERS, visitors = DEFAULT_VISITORS)
    @url = url
    @urners = urners
    @visitors = visitors
  end

  def process
    # TODO: support non-file URLs:
    raise NotImplementedError if pathname.nil?
    @visitors.collect { |v| v.visit_asset(asset) } if asset
  end

  def url
    pathname.to_uri
  end

  def pathname
    paths.try(:last)
  end

  def paths
    pathname = @url.to_pathname
    paths = pathname.follow_redirects
    if paths.nil?
      # the file has been deleted, so mark the assets accordingly
      Asset.with_filename(pathname.to_s).each { |ea| ea.sanity_check! }
      nil
    else
      paths
    end
  end

  def urns
    return nil if paths.nil?
    @urners.collect_hash(ActiveSupport::OrderedHash.new) do |klass|
      t = klass.urn(pathname, exif_result)
      {klass => t} if t
    end
  end

  def paths_to_s
    paths.collect { |ea| ea.to_s }.join(", ")
  end

  def asset
    # Shouldn't happen, because of the findler filters set up in the NextFileProcessor
    return if pathname.nil?

    # TODO: what if there are > 1?
    asset = Asset.with_filename(pathname.to_s).first

    # Short-circuit if the urn and pathname match.
    # This assumes that the first URN changes if the contents for a pathname change.
    if asset
      current_first_urn = @urners.first.urn_for_pathname(pathname)
      return asset unless asset.asset_urns.find_by_urn(current_first_urn).nil?
    end

    # Find the first asset that matches a URN (they're in order of expense of URN generation)
    @urners.each do |urner|
      urn = urner.urn_for_pathname(pathname)
      assets = Asset.with_urn(urn)
      Rails.logger.warn("multiple assets match #{urn}") if assets.size > 1
      asset = assets.first
      break if asset
    end

    asset ||= ExifAsset.create(:basename => pathname.basename.to_s)
    asset_url = asset.add_pathname(pathname)
    asset_url.asset_urns.delete_all # Prior URNs lose.
    @urners.each do |urner|
      urn = urner.urn_for_pathname(pathname)
      asset_url.asset_urns.find_or_create_by_urn(urn)
    end
    asset
  end
end

