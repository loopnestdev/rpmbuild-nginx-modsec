# NGINX Custom RPM Build — RHEL 9 / Rocky Linux 9

This repository contains an RPM spec file and supporting configuration sources to build a custom NGINX package for **RHEL 9 / Rocky Linux 9 (x86_64)**. The build extends the official NGINX SRPM from [nginx.org](http://nginx.org/packages/rhel/9/SRPMS/) with additional dynamic modules and replaces several upstream default configuration files with hardened, production-ready defaults.

---

## Bundled Components

| Component | Version | Description |
|-----------|---------|-------------|
| **NGINX** | 1.26.3 | Base web server (from official NGINX SRPM) |
| [ModSecurity-nginx](https://github.com/SpiderLabs/ModSecurity-nginx) | 1.0.3 | Web Application Firewall (WAF) connector for libmodsecurity v3 |
| [headers-more-nginx-module](https://github.com/openresty/headers-more-nginx-module) | 0.38 | Add, modify, and remove HTTP request/response headers |
| [echo-nginx-module](https://github.com/openresty/echo-nginx-module) | 0.63 | Extended `echo`, `sleep`, and variable inspection directives |
| [nginx-module-vts](https://github.com/vozlt/nginx-module-vts) | 0.2.3 | Virtual host traffic status monitoring dashboard |
| [ngx_http_geoip2_module](https://github.com/leev/ngx_http_geoip2_module) | 3.4 | GeoIP2 country and city lookups (MaxMind databases) |

**Additional dynamic modules** built from the nginx source and included in the package:

- `ngx_http_image_filter_module` (dynamic)
- `ngx_http_xslt_filter_module` (dynamic)

> **Dependency:** [libmodsecurity](https://github.com/SpiderLabs/ModSecurity) **v3.0.13** must be installed on the build host before compiling.

---

## Repository Structure

```
SPECS/
  nginx.spec                   # Custom RPM spec file

SOURCES/
  nginx.conf                   # Custom nginx main config (replaces upstream default)
  nginx.default.conf           # Default server block config
  custom.conf                  # Shared proxy, buffer, and APM log settings
  main.conf                    # ModSecurity main ruleset entry point
  modsecurity.conf             # ModSecurity engine configuration
  modsec_common.conf           # Custom ModSecurity rules reference (not packaged)
  unicode.mapping              # ModSecurity Unicode normalization mapping
  clamav_scan.sh                # Shell script — ClamAV file upload scanning via Clammit
  logrotate                    # NGINX log rotation config (RHEL/Rocky)
  nginx.suse.logrotate         # NGINX log rotation config (SUSE — packaged for spec compatibility)
  nginx.service                # systemd service unit
  nginx-debug.service          # systemd debug service unit
  nginx.upgrade.sh             # Binary upgrade helper script
  nginx.check-reload.sh        # Config check-and-reload helper
  nginx.copyright              # Copyright notice
  ORIGINAL/
    nginx.conf                 # Unmodified upstream nginx.conf (reference only)
```

---

## Prerequisites

- RHEL 9 or Rocky Linux 9 (x86_64)
- Root or `sudo` access for installing packages
- Internet access to download source tarballs from GitHub and nginx.org
- `libmodsecurity` v3.0.13 installed before building (see [Step 2](#step-2--install-libmodsecurity))

---

## Step 1 — Install Build Dependencies

Run all commands in this step as **root** (or prefix with `sudo`).

### Enable required repositories

```bash
# EPEL provides libmodsecurity and libmaxminddb on RHEL 9 / Rocky Linux 9
dnf install -y epel-release

# Enable the CodeReady Builder / CRB repo (provides several -devel packages)
dnf config-manager --set-enabled crb
```

### Install build tools and library headers

```bash
# RPM build toolchain
dnf install -y rpm-build rpmdevtools

# C/C++ compiler and build essentials
dnf install -y gcc gcc-c++ make

# nginx core build dependencies
dnf install -y openssl-devel pcre2-devel zlib-devel

# ModSecurity-nginx connector build dependency
dnf install -y libmodsecurity-devel

# GeoIP2 module build dependency
dnf install -y libmaxminddb-devel

# Image filter module build dependency
dnf install -y gd-devel

# XSLT filter module build dependencies
dnf install -y libxslt-devel libxml2-devel

# ClamAV scan helper runtime dependency
dnf install -y perl
```

---

## Step 2 — Install libmodsecurity

The ModSecurity-nginx connector links against `libmodsecurity`. It must be present on the build host.

Install from EPEL:

```bash
dnf install -y libmodsecurity libmodsecurity-devel libmodsecurity-static
```

If your EPEL version is older than 3.0.13, or you require a specific version, install pre-built RPMs:

```bash
# Adjust filenames/paths to match the RPMs you have
rpm -Uvh libmodsecurity-3.0.13-1.el9.x86_64.rpm \
         libmodsecurity-devel-3.0.13-1.el9.x86_64.rpm \
         libmodsecurity-static-3.0.13-1.el9.x86_64.rpm
```

Verify installation:

```bash
rpm -q libmodsecurity libmodsecurity-devel libmodsecurity-static
```

---

## Step 3 — Create a Dedicated Build User

Building RPMs as a non-root user is strongly recommended. Run as **root**:

```bash
groupadd builder
useradd -d /home/builder -m -s /bin/bash -g builder builder
echo "builder:builder" | chpasswd
```

Switch to the builder account for all remaining steps:

```bash
su - builder
```

---

## Step 4 — Set Up the rpmbuild Directory Tree

```bash
rpmdev-setuptree
```

This creates the standard structure under `~/rpmbuild/`:

```
~/rpmbuild/
  BUILD/
  RPMS/
  SOURCES/
  SPECS/
  SRPMS/
```

---

## Step 5 — Download the NGINX Source RPM

```bash
cd ~
wget http://nginx.org/packages/rhel/9/SRPMS/nginx-1.26.3-1.el9.ngx.src.rpm
rpm -ivh nginx-1.26.3-1.el9.ngx.src.rpm
```

This extracts the official NGINX sources and stock configuration files into `~/rpmbuild/SOURCES/` and the upstream `nginx.spec` into `~/rpmbuild/SPECS/`. Both will be replaced in subsequent steps.

---

## Step 6 — Download Third-Party Module Source Tarballs

Download each module tarball directly into the SOURCES directory:

```bash
cd ~/rpmbuild/SOURCES

# echo-nginx-module v0.63
curl -so echo-nginx-module-0.63.tar.gz \
  https://codeload.github.com/openresty/echo-nginx-module/tar.gz/v0.63

# headers-more-nginx-module v0.38
curl -so headers-more-nginx-module-0.38.tar.gz \
  https://codeload.github.com/openresty/headers-more-nginx-module/tar.gz/v0.38

# nginx-module-vts v0.2.3
curl -so nginx-module-vts-0.2.3.tar.gz \
  https://codeload.github.com/vozlt/nginx-module-vts/tar.gz/v0.2.3

# ModSecurity-nginx connector v1.0.3
curl -so ModSecurity-nginx-1.0.3.tar.gz \
  https://codeload.github.com/SpiderLabs/ModSecurity-nginx/tar.gz/v1.0.3

# ngx_http_geoip2_module v3.4
curl -so ngx_http_geoip2_module-3.4.tar.gz \
  https://codeload.github.com/leev/ngx_http_geoip2_module/tar.gz/3.4
```

Verify all tarballs are present:

```bash
ls -lh ~/rpmbuild/SOURCES/*.tar.gz
```

---

## Step 7 — Copy Custom Source Files from This Repository

The custom files in this repository replace the upstream defaults extracted from the SRPM. Clone or copy this repository to the build host, then run:

```bash
# Set REPO to the path where this repository is cloned
REPO=/path/to/rpmbuild-nginx-modsec

# Custom nginx configuration files (replace upstream originals)
cp "${REPO}/SOURCES/nginx.conf"              ~/rpmbuild/SOURCES/nginx.conf
cp "${REPO}/SOURCES/nginx.default.conf"      ~/rpmbuild/SOURCES/nginx.default.conf
cp "${REPO}/SOURCES/logrotate"               ~/rpmbuild/SOURCES/logrotate
cp "${REPO}/SOURCES/nginx.suse.logrotate"    ~/rpmbuild/SOURCES/nginx.suse.logrotate
cp "${REPO}/SOURCES/nginx.service"           ~/rpmbuild/SOURCES/nginx.service
cp "${REPO}/SOURCES/nginx-debug.service"     ~/rpmbuild/SOURCES/nginx-debug.service
cp "${REPO}/SOURCES/nginx.upgrade.sh"        ~/rpmbuild/SOURCES/nginx.upgrade.sh
cp "${REPO}/SOURCES/nginx.check-reload.sh"   ~/rpmbuild/SOURCES/nginx.check-reload.sh
cp "${REPO}/SOURCES/nginx.copyright"         ~/rpmbuild/SOURCES/nginx.copyright

# Custom ModSecurity and WAF configuration
cp "${REPO}/SOURCES/custom.conf"             ~/rpmbuild/SOURCES/custom.conf
cp "${REPO}/SOURCES/main.conf"               ~/rpmbuild/SOURCES/main.conf
cp "${REPO}/SOURCES/modsecurity.conf"        ~/rpmbuild/SOURCES/modsecurity.conf
cp "${REPO}/SOURCES/unicode.mapping"         ~/rpmbuild/SOURCES/unicode.mapping

# ClamAV file scan helper script
cp "${REPO}/SOURCES/clamd_scan.pl"           ~/rpmbuild/SOURCES/clamd_scan.pl

# Replace the upstream spec with our custom spec
cp "${REPO}/SPECS/nginx.spec"                ~/rpmbuild/SPECS/nginx.spec
```

---

## Step 8 — Build the RPM Package

```bash
rpmbuild -ba --clean ~/rpmbuild/SPECS/nginx.spec
```

The spec performs two configure/make passes:

1. **Debug build** — compiled with `--with-debug`; produces `nginx-debug` binary.
2. **Production build** — standard optimised binary; produces `nginx`.

Both passes compile the same set of dynamic modules. Build time is typically a few minutes on a modern host.

---

## Step 9 — Retrieve the Output Packages

On a successful build, packages are located at:

```
~/rpmbuild/RPMS/x86_64/nginx-1.26.3-1.el9.ngx.x86_64.rpm
~/rpmbuild/SRPMS/nginx-1.26.3-1.el9.ngx.src.rpm
```

List available RPMs:

```bash
ls -lh ~/rpmbuild/RPMS/x86_64/
```

### Install on the build host

```bash
sudo rpm -Uvh ~/rpmbuild/RPMS/x86_64/nginx-1.26.3-1.el9.ngx.x86_64.rpm
```

### Install on remote hosts

Copy the RPM to each target host and install:

```bash
scp ~/rpmbuild/RPMS/x86_64/nginx-1.26.3-1.el9.ngx.x86_64.rpm user@target-host:~
ssh user@target-host "sudo rpm -Uvh nginx-1.26.3-1.el9.ngx.x86_64.rpm"
```

---

## Post-Installation Configuration

### OWASP Core Rule Set (CRS)

The `main.conf` includes paths for the OWASP CRS, which must be installed separately after package installation.

```bash
CRS_VERSION=3.3.5

curl -sL https://github.com/coreruleset/coreruleset/archive/v${CRS_VERSION}.tar.gz \
  | sudo tar xz -C /etc/nginx/owasp --strip-components=1

sudo cp /etc/nginx/owasp/crs-setup.conf.example /etc/nginx/owasp/crs-setup.conf
```

### Start and Enable nginx

```bash
sudo systemctl enable --now nginx
sudo systemctl status nginx
```

---

## Configuration Notes

### nginx.conf — Changes from Upstream Default

The following table summarises the key differences between the custom `nginx.conf` in this repository and the upstream default (preserved in `SOURCES/ORIGINAL/nginx.conf`):

| Setting | Upstream Default | Custom Value | Reason |
|---------|-----------------|--------------|--------|
| `worker_connections` | `1024` | `4096` | Production-level connection capacity |
| `server_tokens` | `on` | `off` | Suppress NGINX version in error pages and `Server` header |
| `variables_hash_max_size` | *(default)* | `1024` | Required to accommodate GeoIP2 variable names |
| `variables_hash_bucket_size` | *(default)* | `128` | Required to accommodate GeoIP2 variable names |
| `proxy_ssl_server_name` | *(absent)* | `on` | Enable SNI when proxying to TLS upstream servers |
| `proxy_ssl_verify` | *(absent)* | `off` | Disable upstream certificate verification (adjust per environment) |
| `vhost_traffic_status_zone` | *(absent)* | enabled | Activates the VTS monitoring zone |
| `log_format main` | basic fields | + `$ssl_protocol $ssl_cipher` | Include TLS negotiation info in access logs |

### Dynamic Module Loading

The following modules are loaded by default in `nginx.conf`:

```nginx
load_module /etc/nginx/modules/ngx_http_headers_more_filter_module.so;
load_module /etc/nginx/modules/ngx_http_geoip2_module.so;
load_module /etc/nginx/modules/ngx_stream_geoip2_module.so;
load_module /etc/nginx/modules/ngx_http_modsecurity_module.so;
load_module /etc/nginx/modules/ngx_http_vhost_traffic_status_module.so;
```

The following modules are compiled and packaged but **commented out** by default — uncomment them as needed:

```nginx
#load_module /etc/nginx/modules/ngx_http_image_filter_module.so;
#load_module /etc/nginx/modules/ngx_http_xslt_filter_module.so;
#load_module /etc/nginx/modules/ngx_http_echo_module.so;
```

### ModSecurity Configuration

ModSecurity is configured via files installed to `/etc/nginx/modsec/`:

| File | Purpose |
|------|---------|
| `modsecurity.conf` | ModSecurity engine settings — rule engine is set to `On` |
| `main.conf` | Top-level include: loads `modsecurity.conf`, OWASP CRS, and custom rules |
| `unicode.mapping` | Unicode table for request normalisation |

> **Detection-only mode:** To observe without blocking, change `SecRuleEngine On` to `SecRuleEngine DetectionOnly` in `/etc/nginx/modsec/modsecurity.conf`.

ModSecurity must be enabled per server block or location. Example:

```nginx
server {
    modsecurity on;
    modsecurity_rules_file /etc/nginx/modsec/main.conf;
    ...
}
```

### Custom ModSecurity Rules (`main.conf`)

`main.conf` includes the following custom rules in addition to the OWASP CRS:

| Rule ID | Phase | Action | Description |
|---------|-------|--------|-------------|
| 2002 | 2 | deny | Virus detected in uploaded file (via ClamAV/Clammit) |
| 2003 | 2 | deny | Block upload of double-extension files (e.g. `file.pdf.php`) |
| 2004 | 1 | deny | Block request URI containing double extensions |
| 2005 | 1 | pass | Disable rule engine for `/hello` health check endpoint |

### GeoIP2 (Optional)

GeoIP2 lookup blocks are included in `nginx.conf` but commented out by default. To activate:

1. Register at [maxmind.com](https://www.maxmind.com/en/geolite2/signup) and download `GeoLite2-Country.mmdb` and/or `GeoLite2-City.mmdb`.
2. Copy the `.mmdb` files to `/etc/nginx/geoip/`.
3. Uncomment the `geoip2` directive blocks in `/etc/nginx/nginx.conf`.
4. Switch to the GeoIP-enabled `log_format main` (also commented out in `nginx.conf`).

Example GeoIP2 log format (already present in `nginx.conf` as a comment):

```nginx
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for" '
                '$ssl_protocol $ssl_cipher '
                '"$geoip2_data_country_code" "$geoip2_data_city_name"';
```

### ClamAV File Upload Scanning

The `clamd_scan.pl` script installed to `/usr/local/bin/` integrates with [Clammit](https://github.com/ifad/clammit) — an HTTP antivirus scanning proxy — listening on `http://127.0.0.1:8438`. ModSecurity rule `2002` invokes this script on every uploaded file during phase 2.

Ensure Clammit and ClamAV (`clamd`) are running before enabling this rule in production.

### APM Logging (`custom.conf`)

`custom.conf` defines two additional `log_format` directives for APM/observability integration:

- **`apm`** — tab-delimited format with upstream timing fields (`$upstream_response_time`, `$upstream_connect_time`, etc.).
- **`apm_json`** — JSON-escaped format suitable for ingestion into log aggregation platforms (Elastic, Splunk, etc.).

Per-location APM logging can be toggled via map files placed in `/etc/nginx/apm.d/*.map`.

---

## Installed Directory Layout

```
/etc/nginx/
├── nginx.conf
├── conf.d/
│   ├── default.conf
│   └── custom.conf
├── modsec/
│   ├── main.conf
│   ├── modsecurity.conf
│   └── unicode.mapping
├── owasp/                   ← Populate with OWASP CRS after install
├── geoip/                   ← Populate with MaxMind .mmdb files
├── ssl/                     ← Place TLS certificates here
└── apm.d/                   ← Place APM map files here

/usr/lib64/nginx/modules/
├── ngx_http_echo_module.so
├── ngx_http_headers_more_filter_module.so
├── ngx_http_vhost_traffic_status_module.so
├── ngx_http_modsecurity_module.so
├── ngx_http_image_filter_module.so
├── ngx_http_xslt_filter_module.so
├── ngx_http_geoip2_module.so
└── ngx_stream_geoip2_module.so

/usr/local/bin/
└── clamd_scan.pl

/var/lib/modsec/upload/      ← ModSecurity temporary upload directory
/var/log/nginx/modsec/       ← ModSecurity audit logs
```

---

## Troubleshooting

### Build fails: `libmodsecurity-devel is needed`

```
error: Failed build dependencies:
    libmodsecurity-devel is needed by nginx-1.26.3-1.el9.ngx.x86_64
```

Ensure EPEL is enabled and install the package:

```bash
dnf install -y epel-release
dnf install -y libmodsecurity-devel
```

If the package is unavailable through EPEL, supply pre-built RPMs (see [Step 2](#step-2--install-libmodsecurity)).

### Build fails: `libmaxminddb-devel is needed`

```bash
dnf install -y epel-release
dnf install -y libmaxminddb-devel
```

### Build fails: `gd-devel` or `libxslt-devel` not found

Enable CRB/PowerTools:

```bash
dnf config-manager --set-enabled crb
dnf install -y gd-devel libxslt-devel libxml2-devel
```

### nginx fails to start after install

Check module load errors:

```bash
journalctl -u nginx --no-pager | head -30
nginx -t
```

Verify all module `.so` files are present:

```bash
ls /usr/lib64/nginx/modules/
```

### ModSecurity blocking legitimate traffic

Switch to detection-only mode while tuning:

```bash
# In /etc/nginx/modsec/modsecurity.conf
SecRuleEngine DetectionOnly
```

Review the audit log for false positives:

```bash
tail -f /var/log/nginx/modsec/audit.log
```

---

## Upgrading to a Newer Version

### Upgrading NGINX

When a new NGINX stable or mainline release appears on [nginx.org/packages/rhel/9/SRPMS/](http://nginx.org/packages/rhel/9/SRPMS/), follow these steps.

#### 1. Update the spec version

Edit `SPECS/nginx.spec` and update the two version defines near the top of the file:

```spec
%define base_version <NEW_NGINX_VERSION>
%define base_release 1%{?dist}.ngx
```

For example, to upgrade from `1.26.3` to `1.28.0`:

```bash
sed -i 's/%define base_version 1.26.3/%define base_version 1.28.0/' SPECS/nginx.spec
```

#### 2. Download the new NGINX source RPM

```bash
NEW_VER=1.28.0

cd ~
wget http://nginx.org/packages/rhel/9/SRPMS/nginx-${NEW_VER}-1.el9.ngx.src.rpm
rpm -ivh nginx-${NEW_VER}-1.el9.ngx.src.rpm
```

This overwrites the NGINX tarball and the stock config files in `~/rpmbuild/SOURCES/`. Re-copy the custom sources from this repository (Step 7) to restore the custom defaults.

#### 3. Re-copy custom source files

```bash
REPO=/path/to/rpmbuild-nginx-modsec

cp "${REPO}/SOURCES/nginx.conf"              ~/rpmbuild/SOURCES/nginx.conf
cp "${REPO}/SOURCES/nginx.default.conf"      ~/rpmbuild/SOURCES/nginx.default.conf
cp "${REPO}/SOURCES/custom.conf"             ~/rpmbuild/SOURCES/custom.conf
cp "${REPO}/SOURCES/main.conf"               ~/rpmbuild/SOURCES/main.conf
cp "${REPO}/SOURCES/modsecurity.conf"        ~/rpmbuild/SOURCES/modsecurity.conf
cp "${REPO}/SOURCES/unicode.mapping"         ~/rpmbuild/SOURCES/unicode.mapping
cp "${REPO}/SOURCES/clamd_scan.pl"           ~/rpmbuild/SOURCES/clamd_scan.pl
cp "${REPO}/SPECS/nginx.spec"                ~/rpmbuild/SPECS/nginx.spec
```

#### 4. Review NGINX changelog for configure-flag changes

Check the upstream changelog for any additions or removals to `--with-*` configure flags:

```bash
curl -s https://nginx.org/en/CHANGES | head -80
```

If new flags should be added (e.g. `--with-http_v3_module` was introduced in 1.25.x), add them to `BASE_CONFIGURE_ARGS` in `SPECS/nginx.spec`.

#### 5. Rebuild the RPM

```bash
rpmbuild -ba --clean ~/rpmbuild/SPECS/nginx.spec
```

#### 6. Tag the release in this repository

After a successful build, commit your spec change and tag the release (see [Release Tagging](#release-tagging) below).

---

### Upgrading a Plugin

Each third-party module is tracked independently. The process is the same regardless of which plugin changes.

#### 1. Identify the new version

Check the upstream release page for the module:

| Module | Releases page |
|--------|---------------|
| headers-more-nginx-module | https://github.com/openresty/headers-more-nginx-module/releases |
| echo-nginx-module | https://github.com/openresty/echo-nginx-module/releases |
| nginx-module-vts | https://github.com/vozlt/nginx-module-vts/releases |
| ModSecurity-nginx | https://github.com/SpiderLabs/ModSecurity-nginx/releases |
| ngx_http_geoip2_module | https://github.com/leev/ngx_http_geoip2_module/releases |
| libmodsecurity | https://github.com/SpiderLabs/ModSecurity/releases |

#### 2. Download the new tarball

```bash
# Example: upgrading headers-more-nginx-module from 0.38 to 0.39
NEW_PLUGIN_VER=0.39

cd ~/rpmbuild/SOURCES
curl -so headers-more-nginx-module-${NEW_PLUGIN_VER}.tar.gz \
  https://codeload.github.com/openresty/headers-more-nginx-module/tar.gz/v${NEW_PLUGIN_VER}
```

#### 3. Update the spec file

In `SPECS/nginx.spec`, update the `Source` line for the module and every reference to the old version string in the `%prep` and `%build` sections.

Example for `headers-more-nginx-module`:

```bash
# Update the Source declaration
sed -i 's/headers-more-nginx-module-0.38/headers-more-nginx-module-0.39/g' SPECS/nginx.spec
```

Three locations in the spec are typically affected per module:

| Section | What to change |
|---------|---------------|
| `Source15:` … `Source19:` | Tarball filename |
| `%prep` | `%{__tar} zxvf %{SOURCE…}` line and `%setup -T -D -a …` line |
| `%build` (both `./configure` blocks) | `--add-dynamic-module=` path |

#### 4. Copy the new tarball to `~/rpmbuild/SOURCES/`

If you edit the spec in this repository first and then sync, this is handled by the copy step above. If editing directly on the build host, the tarball is already in `~/rpmbuild/SOURCES/` from Step 2 of this section.

#### 5. Verify the tarball extracts to the expected directory name

```bash
tar tzf ~/rpmbuild/SOURCES/headers-more-nginx-module-0.39.tar.gz | head -3
```

The first path component printed (e.g. `headers-more-nginx-module-0.39/`) must match the `--add-dynamic-module` path in `nginx.spec`. Adjust the spec if the upstream project uses a different naming scheme.

#### 6. Rebuild and test

```bash
rpmbuild -ba --clean ~/rpmbuild/SPECS/nginx.spec
sudo rpm -Uvh ~/rpmbuild/RPMS/x86_64/nginx-*.x86_64.rpm
nginx -t && sudo systemctl reload nginx
```

#### 7. Upgrading libmodsecurity

`libmodsecurity` is a build-time and run-time dependency, not a compiled-in module. To update it:

```bash
# Install new RPMs (from EPEL or pre-built)
sudo rpm -Uvh libmodsecurity-<NEW_VER>-1.el9.x86_64.rpm \
              libmodsecurity-devel-<NEW_VER>-1.el9.x86_64.rpm

# Rebuild nginx so the linker picks up the new library
rpmbuild -ba --clean ~/rpmbuild/SPECS/nginx.spec
```

Update the version string in the `%post` banner inside `SPECS/nginx.spec` to reflect the new libmodsecurity version.

---

### Release Tagging

After any version change — whether NGINX or a plugin — commit the updated spec, tag the release, and push both to the remote repository.

#### Tag naming convention

Tags follow **NGINX's own version** as the primary identifier, optionally suffixed with a build increment if only plugins or configuration changed:

```
v1.26.3        ← initial build for NGINX 1.26.3
v1.26.3-2      ← rebuild with updated plugin(s), same NGINX version
v1.28.0        ← new NGINX version
```

#### Steps

```bash
# 1. Stage all modified spec and source files
git add SPECS/nginx.spec SOURCES/

# 2. Commit with a descriptive message
git commit -m "nginx 1.26.3 — initial release with ModSecurity, GeoIP2, VTS, headers-more, echo modules"

# 3. Create an annotated tag
git tag -a v1.26.3 -m "NGINX 1.26.3 custom RPM build
- ModSecurity-nginx 1.0.3 / libmodsecurity 3.0.13
- headers-more-nginx-module 0.38
- echo-nginx-module 0.63
- nginx-module-vts 0.2.3
- ngx_http_geoip2_module 3.4"

# 4. Push the commit and tag
git push origin main
git push origin v1.26.3
```

To list all existing release tags:

```bash
git tag --sort=-version:refname | head -10
```
