dos2unix init.sh nftables.conf id_ed25519.pub nftables-common.local syn-flood-detect.sh
scp  -P 2200 init.sh nftables.conf id_ed25519.pub nftables-common.local syn-flood-detect.sh root@${stun}:~
ssh  -p 2200 root@${stun} 'chmod +x ~/init.sh ~/syn-flood-detect.sh && ~/init.sh'
