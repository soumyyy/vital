cask "vital" do
  version "0.1.2"
  sha256 "b8350820761030f1e21df3f358a811f5c4673494aefc85ae11b292b7291e7c18"

  url "https://github.com/soumyyy/vital/releases/download/v#{version}/Vital.dmg"
  name "Vital"
  desc "Menu bar monitor for CPU, memory, storage, and thermals"
  homepage "https://github.com/soumyyy/vital"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Vital.app"

  uninstall quit:       "dev.soumya.vital",
            signal:     [["TERM", "dev.soumya.vital"]],
            on_upgrade: :signal,
            script:     {
              executable: "#{appdir}/Vital.app/Contents/MacOS/Vital",
              args:       ["--unregister-fan-helper"],
              sudo:       false,
            }

  zap trash: "~/Library/Preferences/dev.soumya.vital.plist"
end
