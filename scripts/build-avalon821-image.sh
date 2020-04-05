#!/bin/bash
# This is a script for build avalon controller image
#
#  Copyright 2018- SHI Bin <shibin@canaan-creative.com>
#  Copyright 2018- Zhenxing Xu <xuzhenxing@canaan-creative.com>
#  Copyright 2017-2018 Johnson <fanzixiao@canaan-creative.com>
#  Copyright 2017 Yangjun <yangjun@canaan-creative.com>
#  Copyright 2014-2017 Mikeqin <Fengling.Qin@gmail.com>
#  Copyright 2012-2015 Xiangfu <xiangfu@openmobilefree.com>
#
# OPENWRT_DIR is ${ROOT_DIR}/openwrt, build the image in it
# Controller's image should include the following configurations:
#    ${AVA_MACHINE}_owrepo : OpenWrt repo, format: repo_url@repo_ver
#    feeds.${AVA_MACHINE}.conf : OpenWrt feeds, file locate in cgminer-openwrt-packages
#    ${AVA_TARGET_BOARD}_brdcfg : OpenWrt target and config, file locate in cgminer-openwrt-packages
#
# Learn bash: http://explainshell.com/
set -e

SCRIPT_VERSION=20200328

# Support machine: avalon6, avalon4, abc, avalon7, avalon8, avalon8_lp, avalon9, avalon911, avalonlc3
[ -z "${AVA_MACHINE}" ] && AVA_MACHINE=avalon8

# Support target board: h3, orangepi-2, rpi1-modelb, rpi2-modelb, rpi3-modelb, tl-mr3020-v1, tl-wr703n-v1, wrt1200ac, xc7z100, zedboard, zctrl
[ -z "${AVA_TARGET_BOARD}" ] && AVA_TARGET_BOARD=rpi3-modelb

# Patch repo
[ -z "${PATCH_REPO}" ] && PATCH_REPO=u230925

# OpenWrt repo
OWREPO_PATH="u230925/openwrt-archive"
avalon8_owrepo="git://github.com/"${OWREPO_PATH}".git"

# OpenWrt feeds, features: NULL(Default), NiceHash, DHCP, bitcoind
[ -z "${FEATURE}" ] && FEEDS_CONF_URL=https://raw.github.com/u230925/cgminer-openwrt-packages/master/cgminer/data/feeds.${AVA_MACHINE}.conf
[ "${FEATURE}" == "NiceHash" ] && FEEDS_CONF_URL=https://raw.github.com/u230925/cgminer-openwrt-packages/xnsub/cgminer/data/feeds.${AVA_MACHINE}.conf
[ "${FEATURE}" == "DHCP" ] && FEEDS_CONF_URL=https://raw.github.com/u230925/cgminer-openwrt-packages/dhcp/cgminer/data/feeds.${AVA_MACHINE}.conf
[ "${FEATURE}" == "bitcoind" ] && FEEDS_CONF_URL=https://raw.github.com/u230925/cgminer-openwrt-packages/bitcoind/cgminer/data/feeds.${AVA_MACHINE}.conf

# Board config: target(get it in the OpenWrt bin), config
rpi3_modelb_brdcfg=("brcm2708" "config.${AVA_MACHINE}.rpi3")
rpi2_modelb_brdcfg=("brcm2708" "config.${AVA_MACHINE}.rpi2")
rpi1_modelb_brdcfg=("brcm2708" "config.${AVA_MACHINE}.raspberry-pi")

which wget > /dev/null && DL_PROG=wget && DL_PARA="-nv -O"
which curl > /dev/null && DL_PROG=curl && DL_PARA="-L -o"

# According to http://wiki.openwrt.org/doc/howto/build
unset SED
unset GREP_OPTIONS
[ "`id -u`" == "0" ] && echo "[ERROR]: Please use non-root user" && exit 1
# Adjust CORE_NUM by yourself
[ -z "${CORE_NUM}" ] && CORE_NUM="$(expr $(nproc) + 1)"
DATE=`date +%Y%m%d`
SCRIPT_FILE="$(readlink -f $0)"
SCRIPT_DIR=`dirname ${SCRIPT_FILE}`
ROOT_DIR=${SCRIPT_DIR}/avalon
OPENWRT_DIR=${ROOT_DIR}/openwrt

prepare_version() {
    cd ${OPENWRT_DIR}
    if [ "${AVA_MACHINE}" == "avalon8" ]; then
        GIT_VERSION=`git ls-remote https://github.com/u230925/cgminer avalon821 | cut -f1 | cut -c1-7`
    fi
    LUCI_GIT_VERSION=`git --git-dir=./feeds/luci/.git rev-parse HEAD | cut -c1-7`
    OW_GIT_VERSION=`git --git-dir=./feeds/cgminer/.git rev-parse HEAD | cut -c1-7`

    cat > ./files/etc/avalon_version << EOL
Avalon Firmware for $AVA_MACHINE - $DATE
    luci: $LUCI_GIT_VERSION
    cgminer: $GIT_VERSION
    cgminer-packages: $OW_GIT_VERSION
EOL
}

prepare_config() {
    cd ${OPENWRT_DIR}

    if [ "${AVA_TARGET_BOARD}" == "zctrl" ]; then
        wget https://raw.githubusercontent.com/${PATCH_REPO}/Avalon-extras/master/zctrl-miscs/patches/linux/zynq/config-4.4 -O ./target/linux/zynq/config-4.4
    fi

    if [ "${AVA_TARGET_BOARD}" == "xc7z100" ]; then
        wget https://raw.githubusercontent.com/${PATCH_REPO}/Avalon-extras/master/7z100-miscs/patches/linux/zynq/config-4.4 -O ./target/linux/zynq/config-4.4
        wget https://raw.githubusercontent.com/${PATCH_REPO}/Avalon-extras/master/7z100-miscs/config.7z100 -O ./feeds/cgminer/cgminer/data/config.7z100
    fi

    eval OPENWRT_CONFIG=\${"`echo ${AVA_TARGET_BOARD//-/_}`"_brdcfg[1]} && cp ./feeds/cgminer/cgminer/data/${OPENWRT_CONFIG} .config
}

prepare_feeds() {
    cd ${OPENWRT_DIR}
    $DL_PROG ${FEEDS_CONF_URL} $DL_PARA feeds.conf && \
    ./scripts/feeds update -a && \
    ./scripts/feeds install -a

    if [ ! -e files ]; then
        ln -s feeds/cgminer/cgminer/root-files files
    fi
}

prepare_source() {
    echo "Gen firmware for ${AVA_TARGET_BOARD}:${AVA_MACHINE}"
    echo "TARGET BOARD   :${AVA_TARGET_BOARD}"
    echo "TARGET MACHINE :${AVA_MACHINE}"

    cd ${SCRIPT_DIR}
    [ ! -d avalon ] && mkdir -p avalon/bin
    cd avalon
    if [ ! -d openwrt ]; then
        eval OPENWRT_URL=\${${AVA_MACHINE}_owrepo}
        PROTOCOL="`echo ${OPENWRT_URL} | cut -d : -f 1`"

        case "${PROTOCOL}" in
            git)
                GITBRANCH="`echo ${OPENWRT_URL} | cut -s -d @ -f 2`"
                GITREPO="`echo ${OPENWRT_URL} | cut -d @ -f 1`"
                [ -z ${GITBRANCH} ] && GITBRANCH=master
                git clone ${GITREPO} openwrt
                cd openwrt && git checkout ${GITBRANCH}
                cd ..
                ;;
            svn)
                SVNVER="`echo ${OPENWRT_URL} | cut -s -d @ -f 2`"
                SVNREPO="`echo ${OPENWRT_URL} | cut -d @ -f 1`"
                if [ -z ${SVNVER} ]; then
                    svn co ${SVNREPO}@${SVNVER} openwrt
                else
                    svn co ${SVNREPO} openwrt
                fi
                ;;
            *)
                echo "Protocol not supported"; exit 1;
                ;;
        esac
    fi
    [ ! -e dl ] && mkdir dl
    cd ${OPENWRT_DIR}
    ln -sf ../dl
}

build_image() {
    cd ${OPENWRT_DIR}
    yes "" | make oldconfig > /dev/null
    # clean before build
    make -j${CORE_NUM} clean world
#    make -j1 V=s clean world
}

build_cgminer() {
    cd ${OPENWRT_DIR}
    rm -f ./dl/cgminer-*-avalon*.tar.bz2
    yes "" | make oldconfig > /dev/null
    make -j${CORE_NUM} package/cgminer/{clean,compile}
    if [ "$?" == "0" ]; then
        eval AVA_TARGET_PLATFORM=\${"`echo ${AVA_TARGET_BOARD//-/_}`"_brdcfg[0]}
        cd ..
        mkdir -p ./bin/${AVA_TARGET_BOARD}
        cp ./openwrt/bin/${AVA_TARGET_PLATFORM}/packages/cgminer/cgminer*.ipk  ./bin/${AVA_TARGET_BOARD}
    fi
}

do_release() {
    cd ${ROOT_DIR}
    eval AVA_TARGET_PLATFORM=\${"`echo ${AVA_TARGET_BOARD//-/_}`"_brdcfg[0]}
    echo "Target Platform: ${AVA_TARGET_PLATFORM}"
    mkdir -p ./bin/${DATE}/${AVA_TARGET_BOARD}/
    cp -a ./openwrt/bin/${AVA_TARGET_PLATFORM}/* ./bin/${DATE}/${AVA_TARGET_BOARD}/
}

cleanup() {
    cd ${ROOT_DIR}
    rm -rf openwrt/ > /dev/null
}

show_help() {
    echo "\
Usage: $0 [--version] [--help] [--build] [--cgminer] [--cleanup]

     --version
     --help             Display help message
     --build            Get .config file and build firmware
     --cgminer          Re-compile only cgminer openwrt package
     --cleanup          Remove all files
     AVA_TARGET_BOARD   Environment variable, available target:
                        h3, orangepi-2, pi-modelb-v1, pi-modelb-v2,
                        rpi1-modelb, rpi2-modelb, rpi3-modelb,
                        tl-mr3020-v1, tl-wr703n-v1, wrt1200ac,
                        xc7z100, zedboard, zctrl
                        use rpi3-modelb if unset
     AVA_MACHINE        Environment variable, available machine:
                        avalon911, avalon9, avalon8, avalon8_lp, avalon7, avalon6, avalon4
                        use avalon9 if unset

Written by: Xiangfu <xiangfu@openmobilefree.net>
            Fengling <Fengling.Qin@gmail.com>
            Yangjun <yangjun@canaan-creative.com>
            Johnson <fanzixiao@canaan-creative.com>
            xuzhenxing <xuzhenxing@canaan-creative.com>
            chengping <13641793410@163.com>
            shibin <shibin@canaan-creative.com>
                                                     Version: ${SCRIPT_VERSION}"
 }

if [ "$#" == "0" ]; then
    $0 --help
    exit 0
fi

for i in "$@"
do
    case $i in
        --version|--help)
            show_help
            exit
            ;;
        --build)
            prepare_source && prepare_feeds && prepare_config && prepare_version && build_image && do_release
            ;;
        --cgminer)
            prepare_source && prepare_feeds && prepare_config && prepare_version && build_cgminer
            ;;
        --cleanup)
            cleanup
            ;;
        *)
            show_help
            exit
            ;;
    esac
done

# vim: set ts=4 sw=4 et
