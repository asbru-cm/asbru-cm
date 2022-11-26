# This Dockerfile should be ran from the project's root directory as context path.

FROM alpine:3.13 AS base

WORKDIR /

# Checkout application here
FROM base AS checkout
COPY . /opt/asbru-cm
RUN rm -rf /opt/asbru-cm/.git /opt/asbru-cm/.github /opt/asbru-cm/doc /opt/asbru-cm/scripts

# Common dependencies for both building and running the application
FROM base AS common
RUN apk --no-cache add \
    # Perls
    perl perl-socket6 perl-yaml perl-crypt-cbc perl-glib perl-crypt-rijndael perl-xml-parser perl-io-tty perl-hash-merge-simple \
    # Libs
    libffi pango gtk+3.0 libcanberra-gtk3 gdk-pixbuf librsvg libwnck3 libx11 libxt libxtst dbus-x11 libuuid gobject-introspection libappindicator \
    # Binaries (with libs maybe)
    busybox-extras openssl openssh-client lftp vte3 expect bash \
    # Fonts
    ttf-ubuntu-font-family \
    # Icons
    adwaita-icon-theme \
    # Virtual
    --virtual common-packages-step

# Compiler toolchain and dev libs get installed here
FROM common AS builder
RUN apk --no-cache add \
    # Compiler Toolchain
    gcc g++ musl-dev make \
    # Dev Libs
    perl-dev libx11-dev libffi-dev pango-dev openssl-dev libxt-dev libxtst-dev gobject-introspection-dev \
    # Virtual
    --virtual builder-packages-step

# Pull dependencies here from base image, from cache, to avoid re-pulls during development as much as possible
FROM base AS manual-dependency-puller
RUN apk --no-cache add lftp
RUN cd /tmp && lftp -c "open ftp://ftp.ossp.org; get pkg/lib/uuid/uuid-1.6.2.tar.gz -o ./ossp-uuid-1.6.2.tar.gz"
RUN cd /tmp && wget https://cpan.metacpan.org/authors/id/C/CR/CRAZYDJ/Net-ARP-1.0.11.tgz

# Build manual Perl modules here
FROM builder AS perl-builder
# Pull dependencies from manual puller
COPY --from=manual-dependency-puller /tmp/. /tmp
# Manually compile and install OSSP UUID (no perl package available in APK as of writing)
RUN cd /tmp && tar -zxvf /tmp/ossp-uuid-1.6.2.tar.gz && cd uuid-1.6.2/ && ./configure && make && make install && cd perl && perl Makefile.PL && make && make install && rm -rf ossp-uuid-1.6.2.tar.gz uuid-1.6.2
# Manually compile and install Net::ARP with source patch sed
RUN cd /tmp && tar -zxvf Net-ARP-1.0.11.tgz && cd Net-ARP-1.0.11 && sed -i 's/__THROW//g' arp.h && perl Makefile.PL && make && make install && rm -rf Net-ARP-1.0.11.tgz Net-ARP-1.0.11

# Install Perl modules from CPAN here
FROM perl-builder AS cpan-installer
# Install dependencies from CPAN
RUN apk --no-cache add perl-app-cpanminus --virtual cpanm-installer-packages-step
# Pinned Dependencies with no tests (tests fail, at least on Alpine, even with all libs setup)
RUN cpanm --notest --install RURBAN/Net-Ping-2.74.tar.gz
# Pinned Dependencies with tests
RUN cpanm --notest --install XAOC/Glib-Object-Introspection-0.049.tar.gz
# No-test dependencies (tests fail, at least on Alpine, even with all libs setup)
RUN cpanm --notest --install Net::Proxy
# Testable dependencies
RUN cpanm --install IO::Stty
RUN cpanm --install Glib::IO
RUN cpanm --install Cairo
RUN cpanm --install Cairo::GObject
RUN cpanm --install X11::GUITest
RUN cpanm --install Crypt::Blowfish
RUN cpanm --install Pango
RUN cpanm --install Gtk3
RUN cpanm --install Gtk3::SimpleList
RUN cpanm --install Expect
RUN cpanm --install App::Info::Lib::OSSPUUID
RUN cpanm --install Data::UUID

# Remove as much build-only dependencies as possible
FROM cpan-installer AS stripped-builder
RUN apk --no-cache del cpanm-installer-packages-step builder-packages-step

FROM common AS merged-buildlibs
# Copy built libs, merging with common libs.
COPY --from=stripped-builder /lib/. /lib/
COPY --from=stripped-builder /usr/lib/. /usr/lib/
COPY --from=stripped-builder /usr/local/lib/. /usr/local/lib/
COPY --from=stripped-builder /usr/local/share/. /usr/local/share/
COPY --from=stripped-builder /usr/share/. /usr/share/
COPY --from=stripped-builder /etc/. /etc/

FROM common AS appimage-tools
# Install some needed stuff for AppImage packaging

RUN ping -c 2 "objects.githubusercontent.com" && \
    wget "https://github.com/AppImage/AppImageKit/releases/download/13/appimagetool-x86_64.AppImage" && \
    chmod +x "appimagetool-x86_64.AppImage"

RUN apk add fuse file appstream dos2unix patchelf

RUN wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub

RUN ping -c 2 "objects.githubusercontent.com"

RUN wget "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.34-r0/glibc-2.34-r0.apk" && \
    apk add glibc-2.34-r0.apk

RUN wget "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.34-r0/glibc-bin-2.34-r0.apk" && \
    apk add glibc-bin-2.34-r0.apk

RUN wget "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.34-r0/glibc-i18n-2.34-r0.apk" && \
    apk add glibc-i18n-2.34-r0.apk

RUN /usr/glibc-compat/bin/localedef -i en_US -f UTF-8 en_US.UTF-8

#RUN apk add gcompat

FROM appimage-tools AS appimage-assembler

# Create appimage dir
RUN mkdir -p /var/appimage-dir

# Copy built libs.
COPY --from=merged-buildlibs /lib/. /var/appimage-dir/lib/
COPY --from=merged-buildlibs /usr/lib/. /var/appimage-dir/usr/lib/
COPY --from=merged-buildlibs /usr/local/lib/. /var/appimage-dir/usr/local/lib/
COPY --from=merged-buildlibs /usr/local/share/. /var/appimage-dir/usr/local/share/
COPY --from=merged-buildlibs /usr/share/. /var/appimage-dir/usr/share/
COPY --from=merged-buildlibs /etc/xdg/. /var/appimage-dir/etc/xdg/

# Copy Bins
COPY --from=merged-buildlibs /usr/bin/. /var/appimage-dir/usr/bin

# Copy tree checkout
COPY --from=checkout /opt/asbru-cm/. /var/appimage-dir/opt/asbru-cm/
