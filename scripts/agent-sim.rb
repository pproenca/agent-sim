# Homebrew formula for agent-sim
# Install: brew install pproenca/tap/agent-sim
#
# To set up the tap:
#   1. Create repo github.com/pproenca/homebrew-tap
#   2. Copy this file to Formula/agent-sim.rb
#   3. Update the url and sha256 for each release
#
class AgentSim < Formula
  desc "Simulator automation for AI agents — tap, swipe, read accessibility trees"
  homepage "https://github.com/pproenca/agent-sim"
  url "https://github.com/pproenca/agent-sim/releases/download/v0.1.0/agent-sim-macos-arm64.tar.gz"
  sha256 "1fd62a53af507c7c96c285b68a8b88c4b9db76a31ddedcfa57a43a0c8395d08f"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64
  depends_on :xcode  # iOS Simulators require Xcode

  def install
    # Binary
    bin.install "agent-sim"

    # Dynamic frameworks must be next to the binary (@rpath = @executable_path)
    # Homebrew symlinks bin/agent-sim → ../Cellar/.../bin/agent-sim
    # so we install frameworks into the same directory as the real binary.
    frameworks = %w[FBControlCore FBSimulatorControl FBDeviceControl XCTestBootstrap]
    frameworks.each do |fw|
      (lib/"agent-sim").install "#{fw}.framework"
    end

    # Non-binary assets (commands, skills, templates, references)
    (lib/"agent-sim").install "commands"
    (lib/"agent-sim").install "skills"
    (lib/"agent-sim").install "Templates"
    (lib/"agent-sim").install "references"

    # Claude Code plugin manifest
    (lib/"agent-sim").install ".claude-plugin"

    # Rewrite rpath so the binary finds frameworks in lib/agent-sim/
    system "install_name_tool", "-add_rpath", "#{lib}/agent-sim", bin/"agent-sim"
    # Re-sign after modifying load commands (required on Apple Silicon)
    system "codesign", "--force", "--sign", "-", bin/"agent-sim"
  end

  def post_install
    # Register as Claude Code plugin
    claude_settings = Pathname.new(Dir.home)/".claude"/"settings.json"
    plugin_path = "#{lib}/agent-sim"

    if claude_settings.exist?
      require "json"
      settings = JSON.parse(claude_settings.read)
      plugins = settings.fetch("plugins", [])
      unless plugins.any? { |p| p.include?("agent-sim") }
        plugins << plugin_path
        settings["plugins"] = plugins
        claude_settings.write(JSON.pretty_generate(settings) + "\n")
        ohai "Registered agent-sim as Claude Code plugin"
      end
    else
      claude_settings.dirname.mkpath
      claude_settings.write(JSON.pretty_generate({ "plugins" => [plugin_path] }) + "\n")
      ohai "Registered agent-sim as Claude Code plugin"
    end
  end

  def caveats
    <<~EOS
      agent-sim requires:
        - Xcode (with iOS Simulator runtimes installed)
        - A booted iOS Simulator

      Quick start:
        open -a Simulator
        agent-sim status

      Claude Code plugin:
        agent-sim is automatically registered as a Claude Code plugin.
        Restart Claude Code to use /agentsim:new, /agentsim:replay, etc.
    EOS
  end

  test do
    # --help should work without a simulator
    assert_match "USAGE", shell_output("#{bin}/agent-sim --help")
  end
end
