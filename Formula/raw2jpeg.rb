class Raw2jpeg < Formula
  include Language::Python::Virtualenv

  desc "Convert RAW photos to shareable JPEGs via macOS sips or Core Image"
  homepage "https://github.com/jeancsil/raw2jpeg"
  # NOTE: `main` doesn't yet include this feature branch's commits
  # (pyproject.toml, packaging/, tools/, raw2jpeg package) — `brew install`
  # will fail with this url until jeancsil/raw2jpeg's public main catches up.
  url "https://github.com/jeancsil/raw2jpeg.git", branch: "main"
  version "1.0.0"
  license "MIT"

  depends_on :macos
  # NOT system python: PySide6 needs >=3.10, and macOS ships 3.9.6.
  depends_on "python@3.13"

  # PySide6 (and its own sub-packages) publish only platform-specific wheels
  # on PyPI — no sdist, no py3-none-any wheel — so `virtualenv_install_with_resources`
  # can't be used as-is: Homebrew's Resource#stage leaves the wheel unpacked
  # in a staging directory, and Virtualenv#pip_install only knows to point
  # pip at the file inside that directory for "py3-none-any" wheels. `install`
  # below stages each of these manually and points pip at the wheel file
  # directly instead. URLs/checksums via:
  #   pip install --dry-run --report=- <path-to-this-repo>
  resource "shiboken6" do
    url "https://files.pythonhosted.org/packages/17/f3/f2b63df0251e7cd3172ea28e32ede52739de9566bcefcd0178681538ac81/shiboken6-6.11.1-cp310-abi3-macosx_13_0_universal2.whl"
    sha256 "1a16867f103ef1c662a5f09dfed03273a9f81688b174555162c58e83650a3f02"
  end

  resource "pyside6-essentials" do
    url "https://files.pythonhosted.org/packages/b3/da/10d9197e7370eb4fed8df5fc547b7548dec88e5c5949e2d450db4ae96feb/pyside6_essentials-6.11.1-cp310-abi3-macosx_13_0_universal2.whl"
    sha256 "228de53c2bc26b07e5021fbe3614fc44ca08e4dab9999af08c2b389d2c239957"
  end

  resource "pyside6-addons" do
    url "https://files.pythonhosted.org/packages/3f/6b/8bc94aff48b63f788f2d84e5467c12362d68906ba742c0942f46cb04c879/pyside6_addons-6.11.1-cp310-abi3-macosx_13_0_universal2.whl"
    sha256 "54733c77f789bef5f03c6aff4ad3bec8b2eff021f0cfcbc53d5e6c250ded24f9"
  end

  resource "pyside6" do
    url "https://files.pythonhosted.org/packages/da/a6/27ba5947ed48918f7b74b7c43a1e280aac069e36f25adeb4c9adfac835c4/pyside6-6.11.1-cp310-abi3-macosx_13_0_universal2.whl"
    sha256 "537682c3b7530817203e667c1f5a2f00486b37bf52c52eeab438544c7a0917f6"
  end

  def install
    # Homebrew requires Command Line Tools, so swiftc is guaranteed present —
    # every Homebrew user gets the fast GPU backend rather than it being an
    # optional local build.
    system "swiftc", "-O", "-framework", "CoreImage", "-framework", "ImageIO",
           "-framework", "Metal", "-o", "bin/raw2jpeg-gpu", "tools/raw2jpeg-gpu.swift"
    bin.install "bin/raw2jpeg-gpu"

    # Install PySide6's wheel-only resources by hand (see comment above the
    # resource blocks), then pip-install this package itself and link its
    # console_scripts entry point into bin — the two things
    # virtualenv_install_with_resources normally does together.
    venv = virtualenv_create(libexec, "python3.13")
    %w[shiboken6 pyside6-essentials pyside6-addons pyside6].each do |name|
      res = resource(name)
      res.stage do
        venv.pip_install Pathname.pwd/res.downloader.basename
      end
    end
    venv.pip_install_and_link buildpath

    # Assemble raw2jpeg.app inside the prefix, mirroring `make icon`/`make app`.
    iconset = buildpath/"build/icon.iconset"
    iconset.mkpath
    [16, 32, 128, 256, 512].each do |s|
      system "sips", "-z", s.to_s, s.to_s, "icon.png", "--out", iconset/"icon_#{s}x#{s}.png"
      system "sips", "-z", (s * 2).to_s, (s * 2).to_s, "icon.png",
             "--out", iconset/"icon_#{s}x#{s}@2x.png"
    end
    system "iconutil", "-c", "icns", iconset, "-o", buildpath/"build/icon.icns"

    app = prefix/"raw2jpeg.app"
    (app/"Contents/MacOS").mkpath
    (app/"Contents/Resources").mkpath
    cp "packaging/Info.plist", app/"Contents/Info.plist"
    cp buildpath/"build/icon.icns", app/"Contents/Resources/icon.icns"
    (app/"Contents/MacOS/raw2jpeg").write(
      (buildpath/"packaging/launcher.sh").read.gsub("@PYTHON@", (libexec/"bin/python").to_s),
    )
    chmod 0755, app/"Contents/MacOS/raw2jpeg"
  end

  def caveats
    <<~EOS
      raw2jpeg.app was assembled but not installed, since formulae may not
      write outside their prefix. Copy it into /Applications yourself:

        cp -R "#{opt_prefix}/raw2jpeg.app" /Applications/
    EOS
  end

  test do
    (testpath/"src").mkpath
    system bin/"raw2jpeg", testpath/"src", testpath/"dst", "--dry-run"
  end
end
