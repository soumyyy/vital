cask "vital" do
  version "0.1.3"
  sha256 "94166a5425f0af0cab83dd62dba1b9e9ac2609fc953a08764a4f2d4f5dc1d038"

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
