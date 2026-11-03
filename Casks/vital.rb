cask "vital" do
  version "0.1.4"
  sha256 "c266ab058679e0789b9e88d31617f3595094360d4a2cee724645103a8523f7bd"

  url "https://github.com/soumyyy/vital/releases/download/v#{version}/Vital.dmg"
  name "Vital"
  desc "Menu bar monitor for CPU, memory, storage and thermals"
  homepage "https://github.com/soumyyy/vital"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Vital.app"

  # A menu bar app has no window to open, so start it: the icon appears at once.
  postflight do
    system_command "/usr/bin/open", args: ["-a", "#{appdir}/Vital.app"]
  end

  # Remove the optional fan-control helper registration before the app is deleted.
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
