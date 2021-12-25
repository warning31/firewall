#!/usr/bin/env sh

main() {

    if [ ${USER} != "root" ]; then
        echo "Please login \"root\" user. Not \"admin\" user !"
        exit
    fi

    if [ -f /etc/platform ]; then
        if [ $(cat /etc/platform) = "pfSense" ]; then
            OS_NAME=pfSense
            OS_VERSION=$(cat /etc/version)
            OS_VERSION_MAJOR=$(cat /etc/version | awk -F. '{print $1}')
            OS_VERSION_MINOR=$(cat /etc/version | awk -F. '{print $2}')
            OS_VERSION_REVISION=$(cat /etc/version | awk -F. '{print $3}')

            if [ ${OS_VERSION_MAJOR} != "2" ] || [ ${OS_VERSION_MINOR} -lt "3" ]; then
                echo "Are you sure this operating system is pfSense 2.3.x or later? This installation only works in version 2.3.x or later"
                exit
            fi
        else
            echo "Are you sure this operating system is pfSense?"
        fi
    else
        echo "Are you sure this operating system is pfSense?"
        exit
    fi

    START_PATH=${PWD}
    touch ${START_PATH}/firewall.log
    OUTPUTLOG=${START_PATH}/hotspot.log
    ABI=$(/usr/sbin/pkg config abi)
    FREEBSD_PACKAGE_URL="https://pkg.freebsd.org/${ABI}/latest/All/"
    FREEBSD_PACKAGE_LIST_URL="https://pkg.freebsd.org/${ABI}/latest/packagesite.txz"

    # Defaults
     H_LANG_DEFAULT="en"
     H_MYSQL_ROOT_PASS_DEFAULT="hotspot"
     H_MYSQL_USER_NAME_DEFAULT="hotspot"
     H_MYSQL_USER_PASS_DEFAULT="hotspot"
     H_MYSQL_DBNAME_DEFAULT="hotspot"
     H_ZONE_NAME_DEFAULT="HOTSPOT"
     H_KABLOSUZ_INTERFACES_DEFAULT="opt1"
     H_LAN_INTERFACES_DEFAULT="lan"

    _selectLanguage

    printf "\033c"

    # Gerekli paketler kuruluyor... 

    _installPackages

    echo -e ${L_WELCOME}
    echo

    # User Inputs
    _userInputs

    echo
    echo ${L_STARTING}
    echo

    exec 3>&1 1>>${OUTPUTLOG} 2>&1

    # Ayar Dosyaları Repodan cekiliyor...
    _cloneconfig

    # Cron kuruluyor...
    _cronInstall

    # squid kuruluyor...
    #_squidInstall

    # squidGuard kuruluyor...
    #_squidGuardInstall

    # Hotspot Konfigurasyon yukleniyor...
    _settings

    # Temizlik
    _clean

   # if $(YesOrNo "${L_UNIFIINSTALL}"); then
   #     1>&3
   #     echo -n ${L_UNIFICONTROLLER} 1>&3
   #     fetch -o - https://git.io/j7Jy | sh -s
   #     echo ${L_OK} 1>&3
   # fi
    if $(YesOrNo "${L_RESTARTPFSENSE}"); then
        1>&3
        echo ${L_RESTARTPFSENSE} 1>&3
        /sbin/reboot
    else
        cd /usr/local/hotspot
    fi
}

_selectLanguage() {
 read -p "Select your language (en/tr) [$H_LANG_DEFAULT]: " H_LANG
    H_LANG="${H_LANG:-$H_LANG_DEFAULT}"
    case "${H_LANG}" in
    [eE][nN])
        fetch https://raw.githubusercontent.com/warning31/hotspot/master/config/lang_en.inc
        . lang_en.inc
        ;;
    [tT][rR])
        fetch https://raw.githubusercontent.com/warning31/hotspot/master/config/lang_tr.inc
        . lang_tr.inc
        ;;
    esac
}

_userInputs() {
    read -p "$L_ROOTPASS [$H_MYSQL_ROOT_PASS_DEFAULT]: " H_MYSQL_ROOT_PASS
    H_MYSQL_ROOT_PASS="${H_MYSQL_ROOT_PASS:-$H_MYSQL_ROOT_PASS_DEFAULT}"
    read -p "$L_RADIUSUSERNAME [$H_MYSQL_USER_NAME_DEFAULT]: " H_MYSQL_USER_NAME
    H_MYSQL_USER_NAME="${H_MYSQL_USER_NAME:-$H_MYSQL_USER_NAME_DEFAULT}"
    read -p "$L_RADIUSPASSWORD [$H_MYSQL_USER_PASS_DEFAULT]: " H_MYSQL_USER_PASS
    H_MYSQL_USER_PASS="${H_MYSQL_USER_PASS:-$H_MYSQL_USER_PASS_DEFAULT}"
    read -p "$L_RADIUSDBNAME [$H_MYSQL_DBNAME_DEFAULT]: " H_MYSQL_DBNAME
    H_MYSQL_DBNAME="${H_MYSQL_DBNAME:-$H_MYSQL_DBNAME_DEFAULT}"
    read -p "$L_ZONENAME [$H_ZONE_NAME_DEFAULT]: " H_ZONE_NAME
    H_ZONE_NAME="${H_ZONE_NAME:-$H_ZONE_NAME_DEFAULT}"
    read -p "$L_LAN_INTERFACES [$H_LAN_INTERFACES_DEFAULT]: " H_LAN_INTERFACES
    H_LAN_INTERFACES="${H_LAN_INTERFACES:-$H_KABLOSUZ_INTERFACES_DEFAULT}"
    read -p "$L_KABLOSUZ_INTERFACES [$H_KABLOSUZ_INTERFACES_DEFAULT]: " H_KABLOSUZ_INTERFACES
    H_KABLOSUZ_INTERFACES="${H_KABLOSUZ_INTERFACES:-$H_KABLOSUZ_INTERFACES_DEFAULT}"
}

AddPkg() {
    pkgname=$1
    pkginfo=$(grep "\"name\":\"$pkgname\"" packagesite.yaml)
    pkgvers=$(echo $pkginfo | pcregrep -o1 '"version":"(.*?)"' | head -1)
    echo -n $pkgname 1>&3
    env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg add -f ${FREEBSD_PACKAGE_URL}${pkgname}-${pkgvers}.txz
    echo ${L_OK} 1>&3
}

GetPkgUrl() {
    pkgname=$1
    pkginfo=$(grep "\"name\":\"$pkgname\"" packagesite.yaml)
    pkgvers=$(echo $pkginfo | pcregrep -o1 '"version":"(.*?)"' | head -1)
    echo "/usr/sbin/pkg add -f ${FREEBSD_PACKAGE_URL}${pkgname}-${pkgvers}.txz" 1>&3
}

_installPackages() {

    echo ${L_INSTALLPACKAGES} 1>&3

    if [ ! -f ${PWD}/restarted.qhs ]; then
        exec 3>&1 1>>${OUTPUTLOG} 2>&1
        if ! /usr/sbin/pkg -N 2>/dev/null; then
            env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg bootstrap
        fi

        if ! /usr/sbin/pkg -N 2>/dev/null; then
            echo "ERROR: pkgng installation failed. Exiting."
            exit 1
        fi

        tar xv -C / -f /usr/local/share/pfSense/base.txz ./usr/bin/install

        fetch ${FREEBSD_PACKAGE_LIST_URL}
        tar vfx packagesite.txz

        AddPkg cvsps
        AddPkg p5-Digest-HMAC
        AddPkg p5-GSSAPI
        AddPkg p5-Authen-SASL
        AddPkg p5-HTML-Tagset
        AddPkg p5-Clone
        AddPkg p5-Encode-Locale
        AddPkg p5-TimeDate
        AddPkg p5-HTTP-Date
        AddPkg p5-IO-HTML
        AddPkg p5-LWP-MediaTypes
        AddPkg p5-URI
        AddPkg p5-HTTP-Message
        AddPkg p5-HTML-Parser
        AddPkg p5-CGI
        AddPkg p5-Error
        AddPkg p5-Socket6
        AddPkg p5-IO-Socket-INET6
        AddPkg p5-Mozilla-CA
        AddPkg p5-Net-SSLeay
        AddPkg p5-IO-Socket-SSL
        AddPkg p5-Term-ReadKey
        AddPkg db5
        AddPkg zip
        AddPkg gdbm
        AddPkg apr
        AddPkg serf
        AddPkg utf8proc
        AddPkg libtasn1
        AddPkg bash
        AddPkg bash-completion
        AddPkg p11-kit
        AddPkg gmp
        AddPkg tpm-emulator
        AddPkg trousers
        AddPkg nettle
        AddPkg gnutls
        AddPkg libgpg-error
        AddPkg libassuan
        AddPkg libgcrypt
        AddPkg libksba
        AddPkg npth
        AddPkg pinentry-tty
        AddPkg pinentry-curses
        AddPkg pinentry
        AddPkg gnupg
        AddPkg subversion
        AddPkg p5-subversion
        AddPkg p5-GSSAPI
        AddPkg p5-Authen-SASL
        AddPkg python38
        AddPkg git
        AddPkg wget
        AddPkg nano
        AddPkg libXau
        AddPkg xorgproto
        AddPkg libXdmcp
        AddPkg libpthread-stubs
        AddPkg libxcb
        AddPkg libX11
        AddPkg libXext
        AddPkg png
        AddPkg libslang2
        AddPkg libssh2
        AddPkg libsigsegv
        AddPkg diffutils
        AddPkg mc
        AddPkg cyrus-sasl
        AddPkg lsof
        AddPkg htop
        AddPkg freetype2
        AddPkg protobuf
        AddPkg uchardet
        AddPkg libpaper
        AddPkg psutils
        AddPkg groff
        AddPkg cyrus-sasl
        AddPkg py38-zipp
        AddPkg py38-importlib-metadata
        AddPkg libdaemon
        AddPkg py38-dnspython
        AddPkg py38-markdown
        AddPkg fontconfig
        AddPkg jbigkit
        AddPkg jpeg-turbo
        AddPkg libfontenc
        AddPkg lua53
        AddPkg pixman
        AddPkg tcl86
        AddPkg zstd
        AddPkg tiff
        AddPkg gnome_subr
        AddPkg dbus-glib
        AddPkg avahi-app
        AddPkg gamin
        AddPkg libarchive
        AddPkg libunwind
        AddPkg jansson
        AddPkg talloc
        AddPkg lmdb
        AddPkg tevent
        AddPkg popt
        AddPkg tdb
        AddPkg libsunacl
        AddPkg openssl
       
        

        ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')
        if [ ${ARCH} == "amd64" ]; then
            AddPkg compat10x-amd64
            AddPkg compat9x-amd64
            AddPkg compat8x-amd64
        else
            AddPkg compat10x-i386
            AddPkg compat9x-i386
            AddPkg compat8x-i386
        fi

        #AddPkg php74-mysqli
        #AddPkg php74-pdo_mysql
        #AddPkg php74-iconv
        #AddPkg php74-soap
        #AddPkg php74-odbc
        #AddPkg php74-pdo_dblib
        #AddPkg php74-pdo_odbc
        

        hash -r

        touch ${PWD}/restarted.qhs
        echo -e ${L_RESTARTMESSAGE} 1>&3
        echo ${L_PRESSANYKEY} 1>&3
        read -p "restart" answer
        /sbin/reboot
    fi
}
 
_cloneconfig() {
    echo -n ${L_CLONECONFIG} 1>&3
    cd /usr/local
    git clone https://github.com/warning31/firewall.git
    cd /usr/local/firewall
    cd /usr/local/firewall/config
    echo ${L_OK} 1>&3
}



_cronInstall() {
    /usr/local/sbin/pfSsh.php playback listpkg | grep "cron"
    if [ $? == 0 ]; then
        echo -n ${L_CRONALREADYINSTALLED} 1>&3
    else
        echo -n ${L_CRONINSTALL} 1>&3
        /usr/local/sbin/pfSsh.php playback installpkg "cron"
        hash -r
    fi
    echo ${L_OK} 1>&3
}

#_squidInstall() {
#    /usr/local/sbin/pfSsh.php playback listpkg | grep "squid"
#    if [ $? == 0 ]; then
#        echo -n ${L_CRONALREADYINSTALLED} 1>&3
#    else
#        echo -n ${L_CRONINSTALL} 1>&3
#        /usr/local/sbin/pfSsh.php playback installpkg "squid"
#        hash -r
#    fi
#    echo ${L_OK} 1>&3
#}


#_squidGuardInstall() {
#    /usr/local/sbin/pfSsh.php playback listpkg | grep "squidGuard"
#    if [ $? == 0 ]; then
#        echo -n ${L_CRONALREADYINSTALLED} 1>&3
#    else
#        echo -n ${L_CRONINSTALL} 1>&3
#        /usr/local/sbin/pfSsh.php playback installpkg "squidGuard"
#        hash -r
#    fi
 #   echo ${L_OK} 1>&3
#}


_settings() {
    echo -n ${L_HOTSPOTSETTINGS} 1>&3
    cp /usr/local/firewall/config/config.php /etc/phpshellsessions/config
    sed -i .bak -e "s/{H_MYSQL_USER_NAME}/$H_MYSQL_USER_NAME/g" /etc/phpshellsessions/config
    sed -i .bak -e "s/{H_MYSQL_USER_PASS}/$H_MYSQL_USER_PASS/g" /etc/phpshellsessions/config
    sed -i .bak -e "s/{H_MYSQL_DBNAME}/$H_MYSQL_DBNAME/g" /etc/phpshellsessions/config
    sed -i .bak -e "s/{H_ZONE_NAME}/$H_ZONE_NAME/g" /etc/phpshellsessions/config
    sed -i .bak -e "s/{H_KABLOSUZ_INTERFACES}/$H_KABLOSUZ_INTERFACES/g" /etc/phpshellsessions/config
    sed -i .bak -e "s/{H_LAN_INTERFACES}/$H_LAN_INTERFACES/g" /etc/phpshellsessions/config
    /usr/local/sbin/pfSsh.php playback config
    echo ${L_OK} 1>&3
}

_clean() {
    rm -rf ${START_PATH}/lang_*
#    rm -rf /usr/local/hotspot/config/client.cnf*
   # cp /usr/local/etc/mysql/my.cnfyedek /usr/local/etc/mysql/my.cnf
 #   rm -rf /usr/local/hotspot/config/hotspot.sql*
#   rm -rf /usr/local/hotspot/config/qhotspot.sh*
#    rm -rf /usr/local/hotspot/config/qhotspotconfig.php
}

YesOrNo() {
    while :; do
        echo -n "$1 (yes/no?): " 1>&3
        read -p "$1 (yes/no?): " answer
        case "${answer}" in
        [yY] | [yY][eE][sS]) exit 0 ;;
        [nN] | [nN][oO]) exit 1 ;;
        esac
    done
}

main