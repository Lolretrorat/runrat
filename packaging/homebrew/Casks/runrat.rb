cask "runrat" do
  version "1.0.2"
  sha256 "REPLACE_WITH_RUNRAT_ZIP_SHA256"

  url "https://github.com/Lolretrorat/runrat/releases/download/v#{version}/RunRat-#{version}.zip"
  name "RunRat"
  desc "Native macOS menu bar rat activity monitor"
  homepage "https://github.com/Lolretrorat/runrat"

  app "RunRat.app"
end
