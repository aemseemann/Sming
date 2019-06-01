# sub-directory lwip_open/lwip_full

set(LWIP_SOURCES
    "lwip/core/def.c"
    "lwip/core/dhcp.c"
    "lwip/core/dns.c"
    "lwip/core/init.c"
    "lwip/core/mem.c"
    "lwip/core/memp.c"
    "lwip/core/netif.c"
    "lwip/core/pbuf.c"
    "lwip/core/raw.c"
    "lwip/core/sntp.c"
    "lwip/core/stats.c"
    "lwip/core/sys_arch.c"
    "lwip/core/sys.c"
    "lwip/core/tcp.c"
    "lwip/core/tcp_in.c"
    "lwip/core/tcp_out.c"
    "lwip/core/timers.c"
    "lwip/core/udp.c"
    "lwip/core/ipv4/autoip.c"
    "lwip/core/ipv4/icmp.c"
    "lwip/core/ipv4/igmp.c"
    "lwip/core/ipv4/inet.c"
    "lwip/core/ipv4/inet_chksum.c"
    "lwip/core/ipv4/ip_addr.c"
    "lwip/core/ipv4/ip.c"
    "lwip/core/ipv4/ip_frag.c"
    "lwip/netif/etharp.c"
    "lwip/app/dhcpserver.c"
)
if (SMING_ENABLE_ESPCONN)
    list(APPEND LWIP_SOURCES
        "lwip/app/espconn.c"
        "lwip/app/espconn_tcp.c"
        "lwip/app/espconn_udp.c"
        "lwip/app/espconn_mdns.c"
        "lwip/api/err.c"
        "lwip/core/mdns.c"
    )
else()
    list(APPEND LWIP_SOURCES "espconn_dummy.c")
endif()

add_library(lwip STATIC ${LWIP_SOURCES})

target_include_directories(lwip PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${SDK_BASE}/include"
    "${SMING_HOME}/system/include"
    "${SMING_HOME}/Wiring"
)
target_compile_definitions(lwip PRIVATE
    LWIP_OPEN_SRC 
    PBUF_RSV_FOR_WLAN
    EBUF_LWIP
)
# TBD: why no -finline-functions?
target_compile_options(lwip PRIVATE -mtext-section-literals)

if (SMING_ENABLE_LWIPDEBUG)
    target_compile_definitions(lwip PRIVATE LWIP_DEBUG)
endif()
