# Homebrew Cgit

[![Build Status](https://travis-ci.org/adilinden/homebrew-cgit.svg?branch=master)](https://travis-ci.org/adilinden/homebrew-cgit)

This is my homebrew formula for [cgit], a hyperfast web frontend for git repositories written in C.

## Installation

    brew tap adilinden/homebrew-cgit
    brew install cgit

# How-To

This is how I plumbed nginx & cgit & sshd for a private repository.

## A Dedicated User for Git

Use the OS X dscl tool to create a new user account for git.  Start by finding a uid and gid that is not in use.  This little script can be pasted into a terminal window to find the next uid and guid combo above 501 that is not in use.

```bash
for (( uid = 501; uid<600; uid++ )) ; do \
    if ! id -u $uid &>/dev/null; then \
        if ! dscl . -ls Groups gid | grep -q [^0-9]$uid\$ ; then \
             echo Found: $uid; \
             export this_id=$uid; \
             break; \
        fi; \
    fi; \
done;
```

Now create the git user account.  If the above snippet was run the $this_id variable will already contain the uid and gid to use.

```bash
sudo dscl . -create /Groups/git
sudo dscl . -create /Groups/git Password \*
sudo dscl . -create /Groups/git PrimaryGroupID $this_id
sudo dscl . -create /Groups/git RealName "Git User"
sudo dscl . -create /Groups/git RecordName git

sudo dscl . -create /Users/git
sudo dscl . -create /Users/git NFSHomeDirectory /var/git
sudo dscl . -create /Users/git Password \*
sudo dscl . -create /Users/git PrimaryGroupID $this_id
sudo dscl . -create /Users/git RealName "git User"
sudo dscl . -create /Users/git RecordName git
sudo dscl . -create /Users/git UniqueID $this_id
sudo dscl . -create /Users/git UserShell /usr/bin/git-shell
sudo dscl . -create /Users/git IsHidden 1

sudo dscl . -delete /Users/git AuthenticationAuthority
sudo dscl . -delete /Users/git PasswordPolicyOptions
```

Create the home directory for our new homebrew user account. At the same time create the public key authorization file.

```bash
sudo mkdir -p /var/git/repos
sudo mkdir -p /var/git/.ssh
sudo touch /var/git/.ssh/authorized_keys
sudo chown -R git:git /var/git
```

Init a bare git repo.

```bash
sudo -u git git --bare init /var/git/repos/test.git
```

Now might also be a good time to add a public key to `/var/git/.ssh/authorized_keys` for passwordless public key authentication.

## Run SSH on a Non-Standard Port

I am running ssh on a custom port (2022) for firewall port forwarding reasons.  In order to facilitate this, a new sshd needs to be spawned by the system.  This requires launchctl and sshd configuration.

Create `/etc/ssh/sshd_2022_config`

```
# alternate sshd configuration

# Allow only git
AllowUsers git

# Logging
# obsoletes QuietMode and FascistLogging
SyslogFacility AUTHPRIV
LogLevel INFO

# Allow public key auth
RSAAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile  .ssh/authorized_keys

# Deny password auth
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Deny other auth
KerberosAuthentication no
GSSAPIAuthentication no

# No need for PAM
UsePAM no

# This is OS X default stuff
UsePrivilegeSeparation sandbox      # Default for new installations.
AcceptEnv LANG LC_*
```

Create `/Library/LaunchDaemons/ssh-2022.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Enabled</key>
    <true/>
    <key>Label</key>
    <string>my.sshd</string>
    <key>Program</key>
    <string>/usr/libexec/sshd-keygen-wrapper</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/sbin/sshd</string>
        <string>-i</string>
        <string>-f</string>
        <string>/etc/ssh/sshd_2022_config</string>
    </array>
    <key>Sockets</key>
    <dict>
        <key>Listeners</key>
        <dict>
            <key>SockServiceName</key>
            <string>2022</string>
        </dict>
    </dict>
    <key>inetdCompatibility</key>
    <dict>
        <key>Wait</key>
        <false/>
        <key>Instances</key>
        <integer>42</integer>
    </dict>
    <key>StandardErrorPath</key>
    <string>/dev/null</string>
    <key>POSIXSpawnType</key>
    <string>Interactive</string>
</dict>
</plist>
```

Finally enable the alternate sshd process.

```bash
sudo launchctl load /Library/LaunchDaemons/ssh-2022.plist
```

## FastCGI

Installation of fastcgi.

```bash
brew install fcgiwrap
brew install spawn-fcgi
```

A launchd plist to spawn fcgi. Create `/Library/LaunchDaemons/net.lighttpd.spawn-fcgi.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>net.lighttpd.spawn-fcgi</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>UserName</key>
    <string>www</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/spawn-fcgi</string>
        <string>-n</string>
        <string>-a</string>
        <string>127.0.0.1</string>
        <string>-p</string>
        <string>9000</string>
        <string>--</string>
        <string>/usr/local/sbin/fcgiwrap</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/usr/local/var/www</string>
  </dict>
</plist>
```

Install spawn-fcgi

```bash
sudo launchctl load /Library/LaunchDaemons/net.lighttpd.spawn-fcgi.plist
```

## Nginx

Install the standard nginx (we won't need nginx-full)

```bash
brew install nginx
```

Create self signed ssl certificate.

```bash
mkdir /usr/local/etc/nginx/ssl
cd /usr/local/etc/nginx/ssl
openssl genrsa -des3 -out git-pass.key 1024       # create key
openssl rsa -in git-pass.key -out git.key         # remove pass phrase
openssl req -new -key git.key -out git.csr        # create csr
openssl x509 -req -days 3650 -in git.csr -signkey git.key -out git.crt  # sign csr
```

Configure the server. Replace `/usr/local/etc/nginx/nginx.conf` with:

```
# nginx.conf

user  www;
worker_processes  2;

error_log  /usr/local/var/log/nginx/error.log;
pid        /usr/local/var/run/nginx/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    access_log  /usr/local/var/log/nginx/access.log;

    sendfile        on;
    #tcp_nopush     on;

    #keepalive_timeout  0;
    keepalive_timeout  65;

    include servers/*;
}
```

Create a config file for cgit as `/usr/local/etc/nginx/servers/cgit`.

```
server {
    listen 443;
    server_name _;
    root /usr/local/var/www;

    ssl on;
    ssl_certificate /usr/local/etc/nginx/ssl/git.crt;
    ssl_certificate_key /usr/local/etc/nginx/ssl/git.key;

    # Smart http access to our public repos
    location ~ ^/git(/.*) {
        fastcgi_pass unix:/usr/local/var/run/fcgiwrap.socket;
    
        fastcgi_param SCRIPT_FILENAME /Applications/Xcode.app/Contents/Developer/usr/libexec/git-core/git-http-backend;
        # export all repositories under GIT_PROJECT_ROOT
        fastcgi_param GIT_HTTP_EXPORT_ALL "";
        fastcgi_param GIT_PROJECT_ROOT /var/git/repos;
        fastcgi_param PATH_INFO $1;
        include fastcgi_params;

        #auth_basic "Private Area";
        #auth_basic_user_file /usr/local/etc/nginx/cgit-htpasswd;
    }

    # Smart http is read-only, deny write access
    location ~ ^/git/.*/git-receive-pack$ {
        deny all;
    }

    # Access to our repository
    location /cgit {
        gzip off;
        alias /usr/local/share/cgit;
        try_files $uri @cgit-repo;

        #auth_basic "Private Area";
        #auth_basic_user_file /usr/local/etc/nginx/cgit-htpasswd;
    } 

    location @cgit-repo {
        fastcgi_pass 127.0.0.1:9000;

        # Tell nginx to consider everything after /git as PATH_INFO. This way
        # we get nice, clean URL’s
        fastcgi_split_path_info ^(/cgit)(/?.+)$;

        fastcgi_param  CGIT_CONFIG /var/git/cgitrc-test;
        include /usr/local/etc/nginx/fastcgi_cgit;
    }
}
```

Create the include file /usr/local/etc/nginx/fastcgi_cgit

```
fastcgi_param  QUERY_STRING       $query_string;
fastcgi_param  REQUEST_METHOD     $request_method;
fastcgi_param  CONTENT_TYPE       $content_type;
fastcgi_param  CONTENT_LENGTH     $content_length;

fastcgi_param  REQUEST_URI        $request_uri;
fastcgi_param  DOCUMENT_URI       $document_uri;
fastcgi_param  SERVER_PROTOCOL    $server_protocol;

fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;

fastcgi_param  REMOTE_ADDR        $remote_addr;
fastcgi_param  REMOTE_PORT        $remote_port;
fastcgi_param  SERVER_ADDR        $server_addr;
fastcgi_param  SERVER_PORT        $server_port;
fastcgi_param  SERVER_NAME        $server_name;

fastcgi_param  PATH               /usr/local/bin:/usr/bin:/bin;
fastcgi_param  DOCUMENT_ROOT      /usr/local/share/cgit;
fastcgi_param  SCRIPT_NAME        /cgit.cgi$fastcgi_path_info;
```

Create the password file to access the /git/ location.

```bash
touch /usr/local/etc/nginx/cgit-htpasswd
chmod 640 /usr/local/etc/nginx/cgit-htpasswd
```

Populate with some passwords.

```bash
echo "someuser:{PLAIN}supersecret" > /usr/local/etc/nginx/cgit-htpasswd
```

Test nginx configuration

```bash
 sudo nginx -t
```

Start, restart and stop nginx manually

```bash
sudo nginx
sudo nginx -s reload
sudo nginx -s stop
```

When all is well, perhaps comment out the `auth_basic` directives to enable basic HTTP authentication.

Start and stop with sytem

```bash
sudo cp /usr/local/opt/nginx/homebrew.mxcl.nginx.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/homebrew.mxcl.nginx.plist
```

To restart nginx

```bash
sudo launchctl unload /Library/LaunchDaemons/homebrew.mxcl.nginx.plist
sudo launchctl load /Library/LaunchDaemons/homebrew.mxcl.nginx.plist
```

## Install and Configure Cgit

Install the cgit using homebrew tap

```bash
brew tap adilinden/cgit
brew install cgit
brew install highlight
```

Create a custom highlight configuration for cgit in  `/var/git/syntax-highlighting.sh`.

```bash
#!/bin/sh

# store filename and extension in local vars
BASENAME="$1"
EXTENSION="${BASENAME##*.}"

[ "${BASENAME}" = "${EXTENSION}" ] && EXTENSION=txt
[ -z "${EXTENSION}" ] && EXTENSION=txt

# map Makefile and Makefile.* to .mk
[ "${BASENAME%%.*}" = "Makefile" ] && EXTENSION=mk

# This is for version 3
exec highlight --inline-css --force -f -I -O xhtml -S "$EXTENSION" 2>/dev/null
```

Make sure it is executable.

```bash
sudo -u git chmod 755 /var/git/syntax-highlighting.sh
```

Create `/var/git/cgitrc-test`

```
# cgitrc-test

virtual-root=/cgit/
logo=/cgit/cgit.png
css=/cgit/cgit.css
source-filter=/var/git/syntax-highlighting.sh
enable-commit-graph=1
enable-index-links=1

clone-url=ssh://git@$HTTP_HOST:2022/var/git/$CGIT_REPO_URL.git https://$HTTP_HOST/var/git/$CGIT_REPO_URL.git
enable-http-clone=0

#
# List of git repositories
#

repo.url=test
repo.name=Test Repo
repo.owner=Great Guy <great.guy@example.com>
repo.path=/var/git/repos/test.git
repo.desc=A test repo.
```

[cgit]: http://git.zx2c4.com/cgit/
