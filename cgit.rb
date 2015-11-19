class Cgit < Formula
  desc "A hyperfast web frontend for git repositories written in C."
  homepage "http://git.zx2c4.com/cgit/"
  url "http://git.zx2c4.com/cgit/snapshot/cgit-0.11.2.tar.bz2"
  #version "0.11.2"
  sha256 "1426eeb797af4e2dab174b3b8481c5c8fa7fbf047d7d258d2da19e4f0da2699a"

  depends_on "gettext"
  depends_on "openssl"

  def install

    # Downloads the recommended git source tree
    system "make", "get-git"

    # Install with Debian like paths.
    system "make", "prefix=#{prefix}",
                   "CGIT_SCRIPT_PATH=#{pkgshare}",
                   "install"
  end
end
