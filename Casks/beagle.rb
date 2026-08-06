cask "beagle" do
  version "0.2.12"
  sha256 :no_check # The stable-named asset is replaced on every release.

  url "https://github.com/loom-labs/beagle/releases/latest/download/Beagle-arm64.dmg",
      verified: "github.com/loom-labs/beagle/"
  name "Beagle"
  desc "Local dictation and text-to-speech for macOS"
  homepage "https://loom-labs.github.io/beagle/"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Beagle.app"

  # Beagle stores its settings in UserDefaults and its models in Application
  # Support. Neither is removed on uninstall unless asked for, so reinstalling
  # does not re-download ~1 GB of models.
  zap trash: [
    "~/Library/Application Support/Beagle",
    "~/Library/Caches/ai.loomlabs.beagle",
    "~/Library/Preferences/ai.loomlabs.beagle.plist",
  ]

  caveats <<~EOS
    Beagle lives in the menu bar — there is no Dock icon.

    On first use it downloads ~1 GB of models, then runs entirely offline.

    The first launch is blocked by Gatekeeper, because this build is signed but
    not notarized. Open System Settings > Privacy & Security and click
    "Open Anyway". Homebrew carries that approval forward to later upgrades, so
    it is a one-time step.

    Then grant Accessibility and relaunch Beagle. macOS only hands the
    permission to a freshly launched process, so dictation copies to the
    clipboard until you do.
  EOS
end
