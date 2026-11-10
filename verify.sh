#!/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
cd /root/mephi-results
{
  date --iso-8601=seconds
  cat /etc/os-release
  uname -a
  getconf PAGESIZE
  hostnamectl
  systemctl get-default
} > system.out
{
  nmcli -f GENERAL,IP4 device show
  nmcli -f connection.id,connection.autoconnect,ipv4.method connection show "$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$2!="lo" {print $1;exit}')"
  ip route
} > network.out
{
  lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS
  findmnt /mephi-web
  blkid /dev/vdb1
  findmnt --verify --verbose
} > storage.out 2>&1
{
  rpm -q nginx libcap-ng-utils tcpdump pamtester
  rpm -qi tcpdump
  rpm -q --qf '%{NAME} %{VERSION}-%{RELEASE}\n' redos-release
} > packages.out
{
  systemctl is-enabled nginx
  systemctl is-active nginx
  systemctl show nginx -p RequiresMountsFor
} > services.out
{
  getenforce
  sestatus
  ps -eo label,pid,comm | grep "[n]ginx"
  semanage fcontext -l -C
  ls -Zd /mephi-web /mephi-web/index.html /data/mephi-2026
  matchpathcon -V /mephi-web /mephi-web/index.html
} > selinux.out
{
  for u in student user1 user2 user3 curator1 curator2; do id "$u"; chage -l "$u"; done
  grep '^PASS_MAX_DAYS' /etc/login.defs
  grep -n 'pam_pwquality' /etc/pam.d/system-auth /etc/pam.d/password-auth
  cat /etc/security/pwquality.conf
  if [ -d /etc/security/pwquality.conf.d ]; then grep -RHn '^[[:space:]]*[^#[:space:]]' /etc/security/pwquality.conf.d || true; fi
} > password-policy.out
{
  for u in user1 user2 user3; do
    runuser -u "$u" -- sh -c "umask 077; mkdir -p /data/mephi-2026/${u}-dir; printf '%s\\n' '$u created' > /data/mephi-2026/${u}-dir/example.txt"
  done
  for u in user1 user2 user3; do
    for owner in user1 user2 user3; do
      runuser -u "$u" -- sh -c "printf '%s\\n' '$u edited' >> /data/mephi-2026/${owner}-dir/example.txt"
      echo "PASS $u writes $owner's new file"
    done
  done
  for u in curator1 curator2; do
    for owner in user1 user2 user3; do
      runuser -u "$u" -- cat "/data/mephi-2026/${owner}-dir/example.txt" >/dev/null
      if runuser -u "$u" -- test -w "/data/mephi-2026/${owner}-dir/example.txt"; then echo 'FAIL curator write'; exit 1; fi
      echo "PASS $u reads but cannot write $owner's new file"
    done
    if runuser -u "$u" -- touch "/data/mephi-2026/${u}-forbidden" 2>/dev/null; then echo 'FAIL curator create'; exit 1; fi
    echo "PASS $u cannot create files"
  done
  for u in nobody student; do
    if runuser -u "$u" -- ls /data/mephi-2026 >/dev/null 2>&1; then echo 'FAIL outsider access'; exit 1; fi
    echo "PASS $u has no direct directory access"
  done
} > access-tests.out
getfacl -R -p /data/mephi-2026 > acl.out
{
  for u in curator1 curator2; do
    if pamtester login "$u" acct_mgmt; then echo 'FAIL curator console'; exit 1; fi
    echo "PASS $u denied by local login PAM"
    pamtester sshd "$u" acct_mgmt
    echo "PASS $u not denied by SSH account policy"
  done
  for u in student user1 user2 user3; do
    pamtester login "$u" acct_mgmt
    echo "PASS $u allowed by local login PAM"
  done
} > pam-tests.out 2>&1
# Capture only synthetic ICMP on this VM's loopback, as unprivileged user1.
runuser -u user1 -- timeout 15 tcpdump -p -n -i lo -c 2 icmp > capture.out 2>&1 &
capture_pid=$!
sleep 1
ping -c 1 127.0.0.1 >/dev/null
wait "$capture_pid"
getcap /usr/sbin/tcpdump > getcap.out
[ "$(getenforce)" = Enforcing ]
[ "$(hostname)" = mephi-2026.domain.local ]
[ "$(id -u user1)" = 5501 ]
[ "$(id -u user2)" = 5502 ]
[ "$(id -u user3)" = 5503 ]
[ "$(getent group curators | cut -d: -f3)" = 4444 ]
[ "$(findmnt -n -o FSTYPE /mephi-web)" = ext4 ]
[ "$(curl --fail --silent --show-error http://localhost)" = 'Hello from Student: 374383' ]
stat /data/mephi-2026 > stat.out
stat /mephi-web >> stat.out
getenforce > getenforce.out
curl --fail --silent --show-error http://localhost > curl.out
journalctl -u nginx -b --no-pager > journalctl.out
printf 'PASS: all assertions and functional tests completed\n'
