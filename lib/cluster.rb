require 'mysql'
require "resolv"

class Cluster
    def self.configure(log)
        config_file = ENV["CONFIG_FILE"] || File.expand_path("../config/collector.yml", File.dirname(__FILE__))
        @config=YAML.load_file(config_file)
        @db_connection=nil
        @logger=log
    end
    def self.connect_to_db
        begin
            @db_connection=Mysql.real_connect(@config['cluster_mysql']['host'],@config['cluster_mysql']['username'],@config['cluster_mysql']['password'],@config['cluster_mysql']['db_name'],@config['cluster_mysql']['port'])
        rescue => e
            @logger.error "#{e.message},#{e.backtrace}"
        end
    end
    def self.get_cluster_by_ip(ip)
	begin
        cluster='unknown'
        hostname=Resolv.getname(ip).gsub(".baidu.com","")
        result=@db_connection.query("select cluster from all_hosts where host='#{hostname}'")
        while info=result.fetch_hash
            cluster=info['cluster']
        end
        cluster
	rescue => e
            @logger.error "#{e.message},#{e.backtrace}"
	end
    end
end
