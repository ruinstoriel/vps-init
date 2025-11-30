dos2unix init.sh nftables.conf id_ed25519.pub
scp init.sh nftables.conf id_ed25519.pub root@${stun}:~
ssh root@${stun} 'chmod +x ~/init.sh && ~/init.sh'
