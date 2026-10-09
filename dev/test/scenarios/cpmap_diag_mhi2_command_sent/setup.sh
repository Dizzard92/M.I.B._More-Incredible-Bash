# Module installed and running; two zoom commands reached core.so and the iPhone answered.
. "$(dirname "${BASH_SOURCE[0]}")/../../lib/setup.sh"
cpmap_installed
cpmap_log \
	't_us=1000 pid=40977 event=altscreen-handshake-probe-loaded ptr=0x0 status=0 (0x00000000)' \
	't_us=2000 pid=40977 event=map-control-loopback-ready value1=7032 value2=0 value3=0' \
	't_us=9000 pid=40977 event=map-control-session-remembered ptr=0x1a2b3c status=0 (0x00000000)' \
	't_us=9500 pid=40977 event=alt-video-connected ptr=0x0 status=0 (0x00000000)' \
	't_us=20000 pid=40977 event=map-control-command-request ptr=0x1a2b3c status=0 (0x00000000)' \
	't_us=20100 pid=40977 event=alt-command-completion-changeMapZoomLevel ptr=0x0 status=0 (0x00000000)' \
	't_us=30000 pid=40977 event=map-control-command-request ptr=0x1a2b3c status=0 (0x00000000)' \
	't_us=30100 pid=40977 event=alt-command-completion-changeMapZoomLevel ptr=0x0 status=0 (0x00000000)'
