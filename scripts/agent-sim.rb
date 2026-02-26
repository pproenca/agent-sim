# Homebrew formula for agent-sim
# Install: brew install pproenca/tap/agent-sim
#
# To set up the tap:
#   1. Create repo github.com/pproenca/homebrew-tap
#   2. Copy this file to Formula/agent-sim.rb
#   3. Update the url and sha256 for each release
#
require "fileutils"
require "json"

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
    register_claude_plugin
    sync_claude_skills
    sync_opencode_assets
  end

  def caveats
    <<~EOS
      agent-sim requires:
        - Xcode (with iOS Simulator runtimes installed)
        - A booted iOS Simulator

      Quick start:
        open -a Simulator
        agent-sim status

      AI assets installed:
        Claude skills:  ~/.claude/skills/
        OpenCode:
          skills:   ~/.config/opencode/skills/
          commands: ~/.config/opencode/commands/

      Claude Code plugin:
        ~/.claude/settings.json is updated to include this plugin path.
    EOS
  end

  test do
    # --help should work without a simulator
    assert_match "USAGE", shell_output("#{bin}/agent-sim --help")
  end

  private

  def register_claude_plugin
    claude_settings = Pathname.new(Dir.home)/".claude"/"settings.json"
    plugin_path = "#{lib}/agent-sim"

    settings = if claude_settings.exist?
      JSON.parse(claude_settings.read)
    else
      {}
    end

    plugins = settings.fetch("plugins", [])
    unless plugins.include?(plugin_path)
      plugins << plugin_path
      settings["plugins"] = plugins
      claude_settings.dirname.mkpath
      claude_settings.write(JSON.pretty_generate(settings) + "\n")
      ohai "Registered agent-sim as Claude Code plugin"
    end
  rescue JSON::ParserError
    opoo "Skipping Claude plugin registration: #{claude_settings} has invalid JSON"
  end

  def sync_claude_skills
    src = lib/"agent-sim"/"skills"
    dst = Pathname.new(Dir.home)/".claude"/"skills"
    sync_skill_dirs(src, dst)
    ohai "Synced agent-sim skills to #{dst}"
  end

  def sync_opencode_assets
    root = Pathname.new(Dir.home)/".config"/"opencode"
    skills_dst = root/"skills"
    commands_dst = root/"commands"

    sync_skill_dirs(lib/"agent-sim"/"skills", skills_dst)
    commands_dst.mkpath

    command_map = {
      "new.md" => "agentsim-new.md",
      "replay.md" => "agentsim-replay.md",
      "apply.md" => "agentsim-apply.md",
      "critique.md" => "agentsim-critique.md",
      "tests.md" => "agentsim-tests.md",
    }

    command_map.each do |src_name, dst_name|
      src = lib/"agent-sim"/"commands"/src_name
      next unless src.exist?

      FileUtils.cp(src, commands_dst/dst_name)
    end

    ohai "Synced agent-sim OpenCode assets to #{root}"
  end

  def sync_skill_dirs(src_root, dst_root)
    return unless src_root.exist?

    dst_root.mkpath
    src_root.children.each do |entry|
      next unless entry.directory?

      target = dst_root/entry.basename
      FileUtils.rm_rf(target)
      FileUtils.cp_r(entry, target)
    end
  end
end
