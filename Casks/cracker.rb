cask "cracker" do
  version "1.1.1"
  sha256 :no_check

  url "https://github.com/s3mng/chz-mac/releases/download/v#{version}/cracker-#{version}.dmg"
  name "Cracker"
  desc "Chzzk live recorder and VOD/clip downloader"
  homepage "https://github.com/s3mng/chz-mac"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "Cracker.app"

  zap trash: "~/Library/Containers/app.cracker.mac"
end
