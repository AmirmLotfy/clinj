# Homebrew formula for the Clinj CLI (the menu-bar app ships as a separate cask).
# Tap usage once published:
#   brew tap AmirmLotfy/clinj
#   brew install clinj
#
# Until a tagged release exists, install straight from main:
#   brew install --HEAD AmirmLotfy/clinj/clinj
class Clinj < Formula
  desc "Honest, open-source disk reclaimer for macOS (dynamic cache discovery)"
  homepage "https://github.com/AmirmLotfy/clinj"
  license "MIT"
  head "https://github.com/AmirmLotfy/clinj.git", branch: "main"

  # For tagged releases, fill these in:
  # url "https://github.com/AmirmLotfy/clinj/archive/refs/tags/v2.0.0.tar.gz"
  # sha256 "REPLACE_WITH_TARBALL_SHA256"
  # version "2.0.0"

  def install
    libexec.install "core"
    (libexec/"core/clinj.sh").chmod 0755
    (bin/"clinj").write <<~SH
      #!/bin/bash
      exec "#{libexec}/core/clinj.sh" "$@"
    SH
  end

  test do
    assert_match "Available profiles", shell_output("#{bin}/clinj profiles")
    system "#{bin}/clinj", "scan", "--all", "--json"
  end
end
