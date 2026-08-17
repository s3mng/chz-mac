cask "cracker" do
  version "1.2.1"
  sha256 "41528bf570c8a29322828e6cb55c6f1fcea7c2af73a6ae84345a05d58f027ed8"

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
