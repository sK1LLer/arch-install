#!/bin/bash
select_disk ()
{
  echo -e "\nChoose your disk, cfdisk will start after that.\nYou will have to partition your drive with separate / and /boot partitions"
  select disk_name; do # in "$@" is the default
  if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $(($#)) ];
    then
      break;
    else
      echo "Incorrect Input: Select a number 1-$#"
    fi
  done
}

select_boot_partition ()
{
  echo "Here is what you got:"; lsblk -no NAME,SIZE /dev/$disk_name
  echo -e "\nChoose your BOOT partition:"
  select boot_disk_name; do # in "$@" is the default
  if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $(($#)) ];
    then
      break;
    else
      echo "Incorrect Input: Select a number 1-$#"
    fi
  done
}

select_root_partition ()
{
  echo "Here is what you got:"; lsblk -no NAME,SIZE /dev/$disk_name
  echo -e "\nChoose your root (/) partition:"
  select root_disk_name; do # in "$@" is the default
  if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $(($#)) ];
    then
      break;
    else
      echo "Incorrect Input: Select a number 1-$#"
    fi
  done
}

clear && echo "Hello, this script will install Arch with KDE on BTRFS for you"

[ -d /sys/firmware/efi ] && env="UEFI" || env="BIOS"

echo -e "\nYour disks are:"; lsblk -ndo NAME,SIZE | grep -vE "loop0|sr0"

disks=(); for i in $(lsblk -ndo NAME | grep -vE "loop0|sr0"); do disks+=($i);done
select_disk "${disks[@]}"
sudo cfdisk /dev/$disk_name
clear
partitions=(); for i in $(lsblk -no NAME /dev/$disk_name | grep "─" | sed -e "s|─||g" -e "s|├||g" -e "s|└||g"); do partitions+=($i);done
select_boot_partition "${partitions[@]}" && clear
select_root_partition "${partitions[@]}" && clear

read -p "Enter host name, default is [Arch]: " host_name
host_name=${host_name:-Arch}

echo; read -p "Enter user name, default is [user]: " user_name
user_name=${user_name:-user}

while [ $user_password != $user_password2 ]; do
  echo; read -rsp "Enter password for $user_name, default is [password]:" user_password
  user_password=${user_password:-password}
  echo; read -rsp "Repeat password for $user_name, default is [password]:" user_password2
  user_password2=${user_password2:-password}
done

clear

echo "Your user name is: $user_name"; echo "Your host name is: $host_name"; echo "You have chosen /dev/$disk_name as your disk";echo "You have chosen /dev/$boot_disk_name as your BOOT partiton";echo "You have chosen /dev/$root_disk_name as your ROOT partiton"

read -p "There is no way back! Do we continue y/n? [y]" continue; continue=${continue:-y}; if [[ $continue =~ ^[Yy]$ ]]; then

if [[ $(lscpu | grep "^Vendor ID") == *"AMD"* ]]; then ucode="amd-ucode"; elif [[ $(lscpu | grep "^Vendor ID") == *"Intel"* ]]; then ucode="intel-ucode"; fi
echo "using $ucode"

timedatectl set-timezone Europe/Moscow
echo "timezone set tom Europe/Moscow"

umount -R /mnt 2>/dev/null
# mkfs.vfat -F 32 /dev/$boot_disk_name
mkfs.ext4 /dev/$boot_disk_name

install_btrfs () {
  mkfs.btrfs /dev/$root_disk_name -f

  mount /dev/$root_disk_name /mnt
  btrfs su cr /mnt/@
  btrfs su cr /mnt/@home
  btrfs su cr /mnt/@log
  btrfs su cr /mnt/@snapshots
  umount /mnt

  mount -o noatime,compress=zstd:1,ssd,space_cache=v2,discard=async,subvol=@ /dev/$root_disk_name /mnt
  mkdir -p /mnt/{boot,home,.snapshots,var/log}
  mount -o noatime,compress=zstd:1,ssd,space_cache=v2,discard=async,subvol=@home /dev/$root_disk_name /mnt/home
  mount -o noatime,compress=zstd:1,ssd,space_cache=v2,discard=async,subvol=@snapshots /dev/$root_disk_name /mnt/.snapshots
  #mount -o noatime,compress=zstd:1,ssd,space_cache=v2,discard=async,subvol=@var /dev/$root_disk_name /mnt/var
  mount -o noatime,compress=zstd:1,ssd,space_cache=v2,discard=async,subvol=@log /dev/$root_disk_name /mnt/var/log
}
# echo "what FS to install?"
install_btrfs
mount /dev/$boot_disk_name /mnt/boot


sed -i "s|^#ParallelDownloads.*|ParallelDownloads = 10|g" /etc/pacman.conf
sed -i "s|^#Color|Color|g" /etc/pacman.conf
echo "pacman configured to 10 parallel downloads, choosing best mirrors"

# reflector -c ru,ge,by,us,fi --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
# reflector -c ru,by --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
reflector --latest 20 --threads 5 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
pacman -Syy
plasma_meta="bluedevil breeze-gtk drkonqi kde-gtk-config kdeplasma-addons kgamma kinfocenter krdp kscreen ksshaskpass kwallet-pam ocean-sound-theme plasma-browser-integration plasma-desktop plasma-disks plasma-firewall plasma-nm plasma-pa plasma-systemmonitor plasma-thunderbolt plasma-vault plasma-welcome plasma-workspace-wallpapers powerdevil print-manager sddm-kcm xdg-desktop-portal-kde breeze-grub flatpak-kcm"

#MINIMAL
#pacstrap -K /mnt base linux linux-firmware $ucode fwupd networkmanager btrfs-progs bash-completion grub efibootmgr reflector sudo nano $plasma_meta sddm konsole dolphin kate os-prober

#DEV
#pacstrap -K /mnt base linux linux-firmware $ucode fwupd networkmanager btrfs-progs bash-completion grub efibootmgr reflector sudo nano $plasma_meta sddm konsole dolphin kate os-prober git base-devel

#FULL
pacstrap -K /mnt base linux linux-firmware $ucode fwupd networkmanager btrfs-progs bash-completion grub efibootmgr reflector sudo nano $plasma_meta sddm konsole dolphin kate kde-gtk-config flatpak xdg-desktop-portal-gtk base-devel git firefox spectacle gwenview okular ark kcalc partitionmanager os-prober
#xdg-user-dirs

genfstab -U /mnt | sed "s|,subvolid=.*,|,|g" > /mnt/etc/fstab

cat > /mnt/post-chroot.sh << EOF
sed -i "s|^#ParallelDownloads.*|ParallelDownloads = 10|g" /etc/pacman.conf
sed -i "s|^#Color|Color|g" /etc/pacman.conf

ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
timedatectl set-timezone Europe/Moscow

hwclock --systohc

sed -i "s|^#en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|g" /etc/locale.gen
sed -i "s|^#ru_RU.UTF-8 UTF-8|ru_RU.UTF-8 UTF-8|g" /etc/locale.gen
locale-gen
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo -e "KEYMAP=ru\nFONT=UniCyr_8x16" > /etc/vconsole.conf

echo "$host_name" > /etc/hostname
echo -e "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t$host_name.localdomain\t$host_name" > /etc/hosts
sed -i "s|MODULES=(|MODULES=(btrfs|g" /etc/mkinitcpio.conf
sed -i "s|BINARIES=(|BINARIES=(btrfs|g" /etc/mkinitcpio.conf

#grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi

[ -d /sys/firmware/efi ] && grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot || grub-install --target=i386-pc /dev/$disk_name

#grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot
#grub-install --target=i386-pc /dev/$boot_disk_name

if [[ "$(lspci | grep "VGA compatible controller:")" == *"NVIDIA"* ]]; then
  #sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet nvidia_drm.modeset=1\"|g" /etc/default/grub;
  pacman -Sy nvidia-open nvidia-utils --noconfirm;
  systemctl enable nvidia-suspend.service;
  systemctl enable nvidia-hibernate.service;
  systemctl enable nvidia-resume.service;
elif [[ "$(lspci | grep "VGA compatible controller:")" == *"Iris Xe Graphics"* ]]; then
  pacman -Sy mesa intel-media-driver vulkan-intel --noconfirm;
elif [[ "$(lspci | grep "VGA compatible controller:")" == *"VMware SVGA"* ]]; then
  pacman -Sy virtualbox-guest-utils --noconfirm;
else echo "Video driver installation for ($(lspci | grep VGA) is not implemented"
fi

sed -i "s|^#GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=false|" /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
mkinitcpio -P

systemctl enable sddm
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable systemd-timesyncd

cp /etc/sudoers /etc/sudoers_bckp
sed -i "s|^#\s%wheel ALL=(ALL:ALL) NOPASSWD: ALL|%wheel ALL=(ALL:ALL) NOPASSWD: ALL|g" /etc/sudoers

useradd -G wheel -m -s /bin/bash -p '$(openssl passwd -6 "$user_password")' $user_name

#LC_ALL=C.UTF-8 xdg-user-dirs-update --force

#pacman-key --init && pacman-key --populate && cd /home/$user_name && sudo -u $user_name git clone https://aur.archlinux.org/yay.git && cd yay && sudo -u $user_name makepkg -si --noconfirm && sudo -u $user_name yay -Sy pamac-aur pamac-tray-icon-plasma --noconfirm
pacman-key --init && pacman-key --populate && cd /home/$user_name && sudo -u $user_name git clone https://aur.archlinux.org/yay.git && cd yay && sudo -u $user_name makepkg -si --noconfirm && sudo -u $user_name yay -Sy pamac-aur --noconfirm
sed -i -e "s|^#NoUpdateHideIcon|NoUpdateHideIcon|" -e "s|^RefreshPeriod.*|RefreshPeriod = 3|" -e "s|^#RemoveUnrequiredDeps|RemoveUnrequiredDeps|" -e "s|^#EnableAUR|EnableAUR|" -e "s|^#CheckAURUpdates|CheckAURUpdates|" -e "s|^MaxParallelDownloads.*|MaxParallelDownloads = 10|" /etc/pamac.conf
echo -e "CheckFlatpakUpdates\n\n#EnableSnap\n\nEnableFlatpak" >> /etc/pamac.conf
flatpak override --system --filesystem=xdg-config/gtk-3.0:ro

echo -e "yay -Sy snapper-support btrfs-assistant --noconfirm\nsudo umount /.snapshots\nsudo rm -r /.snapshots\nsudo snapper -c root create-config /\nsudo btrfs subvolume delete -i \\\$(sudo btrfs subvolume list / | grep \\"\\.snapshots\\" | awk -F ' ' '{print \\\$2}') /\nsudo sed -i 's|TIMELINE_LIMIT_HOURLY=.*|TIMELINE_LIMIT_HOURLY=\"0\"|' /etc/snapper/configs/root\nsudo sed -i 's|TIMELINE_LIMIT_DAILY=.*|TIMELINE_LIMIT_DAILY=\"3\"|' /etc/snapper/configs/root\nsudo sed -i 's|TIMELINE_LIMIT_WEEKLY=.*|TIMELINE_LIMIT_WEEKLY=\"0\"|' /etc/snapper/configs/root\nsudo sed -i 's|TIMELINE_LIMIT_MONTHLY=.*|TIMELINE_LIMIT_MONTHLY=\"0\"|' /etc/snapper/configs/root\nsudo sed -i 's|TIMELINE_LIMIT_QUARTERLY=.*|TIMELINE_LIMIT_QUARTERLY=\"0\"|' /etc/snapper/configs/root\nsudo sed -i 's|TIMELINE_LIMIT_YEARLY=.*|TIMELINE_LIMIT_YEARLY=\"0\"|' /etc/snapper/configs/root\nsudo mount -a\nsudo systemctl restart snapperd.service\nsudo bash -c \"echo 'root = \"@snapshots,@,'$(blkid -s UUID -o value /dev/$root_disk_name)'\"' >> /etc/btrfs-assistant.conf\"" > /home/$user_name/backups.sh
chmod +x /home/$user_name/*.sh

cp /etc/sudoers_bckp /etc/sudoers
rm /etc/sudoers_bckp
sed -i "s|^#\s%wheel ALL=(ALL:ALL) ALL$|%wheel ALL=(ALL:ALL) ALL|g" /etc/sudoers
sed -i "s|^Current=.*|Current=breeze|" /usr/lib/sddm/sddm.conf.d/default.conf

exit
EOF

chmod +x /mnt/post-chroot.sh
arch-chroot /mnt /post-chroot.sh
rm /mnt/post-chroot.sh
sync
umount -R /mnt

else echo "stop"; fi
