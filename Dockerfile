FROM alpine:3.20

# Install the packages we need
RUN echo -e "https://dl-cdn.alpinelinux.org/alpine/edge/testing\nhttps://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories &&\
	apk add --update \
	ghostscript \
	hplip \
	avahi \
	inotify-tools \
	python3 \
	python3-dev \
	build-base \
	wget \
	rsync \
	py3-pycups \
	perl \
	# CUPS build dependencies
	openssl-dev \
	zlib-dev \
	libusb-dev \
	libpng-dev \
	libjpeg-turbo-dev \
	gnutls-dev \
	krb5-dev \
	acl-dev \
	linux-pam-dev \
	&& rm -rf /var/cache/apk/*

# Create cups user and group
RUN addgroup -S cups && adduser -S -G cups cups && \
    addgroup -S lpadmin && adduser -S -G lpadmin lpadmin

# Build and install CUPS from source
RUN wget https://github.com/OpenPrinting/cups/releases/download/v2.4.12/cups-2.4.12-source.tar.gz && \
    tar xzf cups-2.4.12-source.tar.gz && \
    cd cups-2.4.12 && \
    ./configure --prefix=/usr \
                --sysconfdir=/etc \
                --localstatedir=/var \
                --with-cups-user=cups \
                --with-cups-group=cups \
                --with-system-groups=lpadmin \
                --enable-raw-printing \
                --disable-pam \
                --enable-dbus=no \
                --enable-libusb \
                --enable-shared \
                --enable-relro \
                --enable-acl && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf cups-2.4.12 cups-2.4.12-source.tar.gz

# Build and install brlaser from source
RUN apk add --no-cache git cmake && \
    git clone https://github.com/pdewacht/brlaser.git && \
    cd brlaser && \
    cmake . && \
    make && \
    make install && \
    cd .. && \
    rm -rf brlaser

# Build and install gutenprint from source
RUN wget -O gutenprint-5.3.5.tar.xz https://sourceforge.net/projects/gimp-print/files/gutenprint-5.3/5.3.5/gutenprint-5.3.5.tar.xz/download && \
    tar -xJf gutenprint-5.3.5.tar.xz && \
    cd gutenprint-5.3.5 && \
    # Patch to rename conflicting PAGESIZE identifiers to GPT_PAGESIZE in all files in src/testpattern
    find src/testpattern -type f -exec sed -i 's/\bPAGESIZE\b/GPT_PAGESIZE/g' {} + && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf gutenprint-5.3.5 gutenprint-5.3.5.tar.xz && \
    # Fix cups-genppdupdate script shebang
    sed -i '1s|.*|#!/usr/bin/perl|' /usr/sbin/cups-genppdupdate

# This will use port 631
EXPOSE 631

# We want a mount for these
VOLUME /config
VOLUME /services

# Add scripts
ADD root /
RUN chmod +x /root/*

#Run Script
CMD ["/root/run_cups.sh"]

# Baked-in config file changes
RUN sed -i 's/Listen localhost:631/Listen 0.0.0.0:631/' /etc/cups/cupsd.conf && \
	sed -i 's/Browsing On/Browsing Off/' /etc/cups/cupsd.conf && \
 	sed -i 's/IdleExitTimeout/#IdleExitTimeout/' /etc/cups/cupsd.conf && \
	sed -i 's/<Location \/>/<Location \/>\n  Allow All/' /etc/cups/cupsd.conf && \
	sed -i 's/<Location \/admin>/<Location \/admin>\n  Allow All\n  Require user @SYSTEM/' /etc/cups/cupsd.conf && \
	sed -i 's/<Location \/admin\/conf>/<Location \/admin\/conf>\n  Allow All/' /etc/cups/cupsd.conf && \
	echo "ServerAlias *" >> /etc/cups/cupsd.conf && \
	echo "DefaultEncryption Never" >> /etc/cups/cupsd.conf && \
	echo "ReadyPaperSizes A4,TA4,4X6FULL,T4X6FULL,2L,T2L,A6,A5,B5,L,TL,INDEX5,8x10,T8x10,4X7,T4X7,Postcard,TPostcard,ENV10,EnvDL,ENVC6,Letter,Legal" >> /etc/cups/cupsd.conf && \
	echo "DefaultPaperSize Letter" >> /etc/cups/cupsd.conf && \
	echo "pdftops-renderer ghostscript" >> /etc/cups/cupsd.conf && \
	echo "BrowseAllow none" >> /etc/cups/cupsd.conf && \
	echo "BrowseDeny all" >> /etc/cups/cupsd.conf && \
	echo "BrowseProtocols none" >> /etc/cups/cupsd.conf && \
	echo "BrowseLocalProtocols none" >> /etc/cups/cupsd.conf && \
	echo "BrowseRemoteProtocols none" >> /etc/cups/cupsd.conf && \
	echo "BrowseOrder deny,allow" >> /etc/cups/cupsd.conf && \
	echo "BrowseAddress @LOCAL" >> /etc/cups/cupsd.conf && \
	echo "BrowsePoll none" >> /etc/cups/cupsd.conf && \
	echo "BrowseInterval 0" >> /etc/cups/cupsd.conf && \
	echo "BrowseTimeout 0" >> /etc/cups/cupsd.conf && \
	echo "BrowseShortNames No" >> /etc/cups/cupsd.conf && \
	echo "UseCUPSGeneratedPPDs No" >> /etc/cups/cupsd.conf && \
	echo "DisableDNSSD Yes" >> /etc/cups/cupsd.conf && \
	echo "DisableAvahi Yes" >> /etc/cups/cupsd.conf && \
	# Configure Avahi to not interfere with CUPS
	sed -i 's/.*enable\-dbus=.*/enable\-dbus\=no/' /etc/avahi/avahi-daemon.conf && \
	sed -i 's/.*use\-ipv4=.*/use\-ipv4\=yes/' /etc/avahi/avahi-daemon.conf && \
	sed -i 's/.*use\-ipv6=.*/use\-ipv6\=no/' /etc/avahi/avahi-daemon.conf && \
	sed -i 's/.*deny\-interfaces=.*/deny\-interfaces\=lo/' /etc/avahi/avahi-daemon.conf && \
	sed -i 's/.*use\-iff\-running=.*/use\-iff\-running\=no/' /etc/avahi/avahi-daemon.conf && \
	sed -i 's/.*enable\-reflector=.*/enable\-reflector\=no/' /etc/avahi/avahi-daemon.conf && \
	sed -i 's/.*reflect\-ipv=.*/reflect\-ipv\=no/' /etc/avahi/avahi-daemon.conf && \
	sed -i 's/.*rlimit\-nofile=.*/rlimit\-nofile\=768/' /etc/avahi/avahi-daemon.conf
