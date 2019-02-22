class Cgit < Formula
  desc "A hyperfast web frontend for git repositories written in C."
  homepage "http://git.zx2c4.com/cgit/"
  url "https://git.zx2c4.com/cgit/snapshot/cgit-0.11.2.tar.xz"
  #version "0.11.2"
  sha256 "2e126e770693d7296c7eb5eb83b809410aef29870bfe8f54da072a3f4d813e3b"

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
