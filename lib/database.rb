require "activerecord-jdbcmysql-adapter"
class CollectorDb < ActiveRecord::Base
    def self.configure(config)
        self.abstract_class = true
        establish_connection(
            :adapter => "mysql",
            :host =>config["mysql"]["host"],
            :database =>config["mysql"]["db_name"],
            :username =>config["mysql"]["username"],
            :password =>config["mysql"]["password"],
            :port =>config["mysql"]["port"],
            :pool => 10,
            :reconnect => true
        )
    end
end

class InstanceStatus < CollectorDb
	self.table_name="instance_status"
end

class DeaList < CollectorDb  
    self.table_name="dea_list"
end 

class ClusterDb < ActiveRecord::Base
    def self.configure(config)
        self.abstract_class = true
        establish_connection(
            :adapter => "mysql",
            :host =>config["cluster_mysql"]["host"],
            :database =>config["cluster_mysql"]["db_name"],
            :username =>config["cluster_mysql"]["username"],
            :password =>config["cluster_mysql"]["password"],
            :port =>config["cluster_mysql"]["port"],
            :pool => 10,
            :reconnect => true
        )
    end
end

class AllHosts < ClusterDb
    self.table_name="all_hosts"
end 
