cask "vital" do
  version "0.1.6"
  sha256 "b7b8b64df2fc48e955c0a60f17d641016f3bd20d8c9a04fc295cc105bef89af0"

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
  binary "#{appdir}/Vital.app/Contents/MacOS/Vital", target: "vital"

  # A menu bar app has no window to open, so start it: the icon appears at once. This uses the block form because
  # `postflight_steps` runs in a sandbox that cannot reach Launch Services; a failed launch must not fail the install.
  postflight do
    system_command "/usr/bin/open", args: ["-a", "#{appdir}/Vital.app"], must_succeed: false
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
