#!/usr/bin/env bash
# 6.16.1-atas6 cekirdegi: atas5 + DAGITIM ICIN DONANIM DESTEGI (v30 testinde bulunan eksikler)
#   Ekran kartlari: AMD (amdgpu, eski kartlar icin SI/CIK, radeon), NVIDIA (nouveau), sanal makineler
#     (bochs = QEMU std VGA, vmwgfx = VMware/VirtualBox VMSVGA, vboxvideo). Firmware'leri atasOS'ta zaten var.
#   AMD dizustu: PINCTRL_AMD (dokunmatik yuzey kesmeleri), amd-pstate, k10temp, AMD PMC (uyku), ACP ses.
#   WiFi: MediaTek MT7921/7922 (PCIe + USB), MT76x2U, Realtek RTW88/RTW89 ek yongalar, RTL8XXXU (USB).
#   USB_UAS (hizli USB3 diskler), IKCONFIG_PROC (/proc/config.gz).
# atas5'e ve GRUB'daki "atasOS" girdisine DOKUNMAZ; atas6 ayri bir GRUB dosyasiyla (45_atasos_atas6) eklenir.
# Kullanim: sudo bash /home/eren/atasos-58-cekirdek-atas6.sh     (derleme 40-90 dk; amdgpu buyuk)
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
A=/mnt/atasos
K=$A/sources/linux-6.16.1
YENI=6.16.1-atas6
TABAN=6.16.1-atas5
LOG=/home/eren/atas3-loglar/derleme-atas6-$(date +%m%d-%H%M).log
P5UUID=652f2262-d729-4c56-9eb4-ed463d94644a
PARTUUID=524c28d4-f588-4154-b586-6654380d7f22
J=$(nproc)
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir. Hicbir sey yapilmadi."; exit 1; }
mkdir -p $A; mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
trap 'sync; cd /; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"; chown eren:eren "$LOG" 2>/dev/null' EXIT
[ -f $A/boot/config-$TABAN ] || { echo "HATA: $A/boot/config-$TABAN yok"; exit 1; }
cd "$K" || { echo "HATA: $K yok"; exit 1; }

echo "########## 1/7  YAPILANDIRMA (atas3 + eklemeler) ##########"
cp .config .config.onceki-$(date +%m%d-%H%M) 2>/dev/null
cp $A/boot/config-$TABAN .config
Y="IKCONFIG IKCONFIG_PROC PINCTRL_AMD X86_AMD_PSTATE DRM_AMDGPU_SI DRM_AMDGPU_CIK DRM_AMD_DC DRM_AMDGPU_USERPTR HSA_AMD"
M="DRM_AMDGPU DRM_RADEON DRM_NOUVEAU DRM_BOCHS DRM_VMWGFX DRM_VBOXVIDEO DRM_QXL \
   SENSORS_K10TEMP AMD_PMC AMD_PMF SND_SOC_AMD_ACP SND_SOC_AMD_RENOIR SND_SOC_AMD_RENOIR_MACH SND_SOC_AMD_ACP6x SND_SOC_AMD_YC_MACH \
   SND_SOC_AMD_PS SND_SOC_AMD_PS_MACH SND_PCI_ACP3X SND_AMD_ACP_CONFIG I2C_PIIX4 \
   MT7921E MT7921U MT7925E MT76x2U MT7601U RTW88_8821CE RTW88_8822BE RTW89_8852BE RTW89_8852CE RTL8XXXU RTW88_8821CU RTW88_8822BU \
   USB_UAS"
A1=(); for o in $Y; do A1+=(--enable "$o"); done; for o in $M; do A1+=(--module "$o"); done
scripts/config --file .config --set-str LOCALVERSION "-atas6" "${A1[@]}"
make olddefconfig > /dev/null 2>&1 || { echo "HATA: make olddefconfig"; exit 1; }
# zorunlu olanlar: biri tutmazsa derleme baslamaz
ZOR="DRM_AMDGPU DRM_NOUVEAU DRM_RADEON IKCONFIG_PROC MT7921E USB_UAS"
B=0
for o in $Y $M; do
    v=$(grep -E "^CONFIG_$o=" .config | cut -d= -f2); v=${v:-KAPALI}
    if [ "$v" = y ] || [ "$v" = m ]; then printf '  %-30s %s\n' "$o" "$v"
    else case " $ZOR " in *" $o "*) printf '  %-30s %s <<< ZORUNLU\n' "$o" "$v"; B=1;; *) printf '  %-30s %s (bagimlilik yok, atlandi)\n' "$o" "$v";; esac; fi
done
# atas3'un acilisi icin sart olanlar korunmus mu
for o in DRM DRM_SIMPLEDRM FRAMEBUFFER_CONSOLE BLK_DEV_NVME EXT4_FS SQUASHFS OVERLAY_FS ISO9660_FS DEVTMPFS_MOUNT SND_HDA_INTEL SND_HDA_CODEC_REALTEK I2C_HID_ACPI; do
    grep -q "^CONFIG_$o=y" .config || { echo "  $o artik =y degil <<<"; B=1; }; done
LV=$(grep '^CONFIG_LOCALVERSION=' .config | cut -d= -f2 | tr -d '"')
[ "$LV" = "-atas6" ] || { echo "  LOCALVERSION $LV <<<"; B=1; }
echo "  atas5'e gore degisen satir: $(diff <(grep '^CONFIG_' $A/boot/config-$TABAN | sort) <(grep '^CONFIG_' .config | sort) | grep -c '^>')"
[ $B -eq 0 ] || { echo; echo "  SORUN VAR. Derleme baslatilmadi (.config atas6 hali kaldi; atas5 /boot'ta yerinde)."; exit 1; }

echo
echo "########## 2/7  DERLEME (make -j$J) ##########"
echo "  bos disk (p5): $(df -h $A | tail -1 | awk '{print $4}')   log: $LOG"
BAS=$(date +%s)
( make -j"$J" > "$LOG" 2>&1; echo "MAKE_CIKIS=$?" >> "$LOG" ) &
PID=$!
while kill -0 "$PID" 2>/dev/null; do
    sleep 30
    printf '    %s  %6s satir  |  %s\n' "$(date '+%H:%M:%S')" "$(wc -l < "$LOG")" "$(grep -E '^\s+(CC|LD|AR)\s' "$LOG" | tail -1 | awk '{print $NF}')"
done
wait "$PID" 2>/dev/null
grep -q '^MAKE_CIKIS=0$' "$LOG" || { echo "  DERLEME BASARISIZ <<<"; grep -iE 'error|Error [0-9]' "$LOG" | tail -20 | sed 's/^/    /'; echo "  atas5 yerinde, hicbir sey kurulmadi."; exit 1; }
echo "  derleme bitti ($(( ($(date +%s)-BAS)/60 )) dk)"

echo
echo "########## 3/7  DOGRULAMA ##########"
IMG=arch/x86/boot/bzImage
SURUM=$(make -s kernelrelease 2>/dev/null)
echo "  kernelrelease: $SURUM   bzImage: $(du -h $IMG | cut -f1)"
[ "$SURUM" = "$YENI" ] || { echo "  HATA: surum $YENI degil. Kurulum iptal."; exit 1; }

echo
echo "########## 4/7  MODULLER ##########"
MD=$A/usr/lib/modules
[ -d "$MD/$YENI" ] && rm -rf "${MD:?}/$YENI"
make -s modules_install INSTALL_MOD_PATH="$A" INSTALL_MOD_STRIP=1 2>&1 | tail -3 | sed 's/^/    /'
depmod -b "$A" "$YENI" && echo "  $YENI: $(find $MD/$YENI -name '*.ko*' | wc -l) modul, depmod tamam"
for m in amdgpu radeon nouveau bochs vmwgfx mt7921e uas k10temp i915 iwlwifi uvcvideo huawei-wmi fuse; do
    f=$(find $MD/$YENI -name "${m}.ko*" -o -name "$(echo $m | tr - _).ko*" | head -1)
    printf '    %-22s %s\n' "$m" "$( [ -n "$f" ] && echo modul || (grep -q "$(echo $m | tr - _)" $MD/$YENI/modules.builtin 2>/dev/null && echo gomulu || echo YOK))"
done

echo
echo "########## 5/7  /boot ##########"
cp $IMG $A/boot/vmlinuz-$YENI; cp System.map $A/boot/System.map-$YENI; cp .config $A/boot/config-$YENI
ls -la $A/boot/vmlinuz-* | sed 's/^/  /'

echo
echo "########## 6/7  GRUB (Kubuntu) - yeni dosya, mevcut girdilere dokunulmaz ##########"
G=/etc/grub.d/45_atasos_atas6
cat > $G <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry "atasOS (atas6 - yeni cekirdek, deneme)" --class atasos {
    insmod part_gpt
    insmod ext2
    insmod all_video
    insmod gfxterm
    set gfxpayload=keep
    search --no-floppy --fs-uuid --set=root $P5UUID
    linux /boot/vmlinuz-$YENI root=PARTUUID=$PARTUUID rw rootwait console=tty0 loglevel=4
}
EOF
chmod 755 $G
update-grub 2>&1 | grep -iE 'atas|error|done|bitti' | sed 's/^/  /'
grep -n 'menuentry "atasOS' /boot/grub/grub.cfg | sed 's/^/  /'

echo
echo "########## 7/7  OZET ##########"
echo "  Yeniden baslat -> GRUB'da 'atasOS (atas6 - yeni cekirdek, deneme)'."
echo "  Sorun olursa 'atasOS' girdisi (atas5) aynen yerinde. Sonraki ISO en yeni cekirdegi (atas6) kullanir."
