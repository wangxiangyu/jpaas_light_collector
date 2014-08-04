require "resolv"
require "database"

class Cluster
    def self.configure(log)
        config_file = ENV["CONFIG_FILE"] || File.expand_path("../config/collector.yml", File.dirname(__FILE__))
        @config=YAML.load_file(config_file)
        @logger=log
        ClusterDb.configure(@config)
    end
    def self.get_cluster_by_ip(ip)
        begin
            cluster='unknown'
            hostname=Resolv.getname(ip).gsub(".baidu.com","")
            result=AllHosts.where(:host=>hostname)
            cluster=result.first.cluster unless result.empty?
            cluster
        rescue => e
            @logger.error "#{e.message},#{e.backtrace}"
        end
    end
end
