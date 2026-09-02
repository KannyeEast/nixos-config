{
  flake.modules.nixos.dns =
    { config, ... }:
    {
      config = {
        # Free port 53 for blocky to use
        services.resolved.settings.Resolve.DNSStubListener = false;
        
        services.blocky = {
          enable = true;
          settings = {
            ports = {
              dns = 53;
              http = 4000;
            };
            
            # HTTPS over DNS 
            upstreams.groups.default = [
              "https://security.cloudflare-dns.com/dns-query"
              "https://dns.quad9.net/dns-query"
            ];
            bootstrapDns = "tcp+udp:1.1.1.1";
            
            conditional.mapping."ts.net" = "100.100.100.100";
            
            blocking = {
              denylists.ads = [
                "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
              ];
              clientGroupsBlock.default = [
                "ads"
              ];
              blockType = "zeroIp";
            };
            
            caching = {
              minTime = "5m";
              maxTime = "30m";
              prefetching = true;
            };
            
            queryLog.type = "console";
            prometheus.enable = true;
          };
        };
        
        networking.firewall.interfaces.${config.services.tailscale.interfaceName} = {
          allowedTCPPorts = [ 
            53 
          ];
          allowedUDPPorts = [ 
            53 
          ];          
        };
        
        internal.server.proxy.services.blocky = {
          port = 4000;
        };
      };
    };
}
