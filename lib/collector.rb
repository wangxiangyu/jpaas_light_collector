require 'sinatra/base'
require 'sinatra/synchrony'
require 'mysql'
require 'json'
require "yaml"
require "logger"
require "database"
require "resolv"
require "cluster"


class Collector < Sinatra::Base
    register Sinatra::Synchrony
    disable :logging
    def self.configure
         config_file = ENV["CONFIG_FILE"] || File.expand_path("../config/collector.yml", File.dirname(__FILE__))
         @config=YAML.load_file(config_file)
         set :bind, '0.0.0.0'
         set :port, @config["listen_port"]
         set :server, 'thin'
    end
    attr_reader :config
    attr_reader :mysql_conn
    attr_reader :logger
    def self.connect_to_db
       begin
            CollectorDb.configure(@config)
       rescue =>e
            @logger.error "#{e.message},#{e.backtrace}"
       end
    end
    
    def self.setup_log 
       @logger=Logger.new(@config['logging']['file'])
       @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
       @logger.formatter = proc do |severity, datetime, progname, msg|
           "[#{datetime}] #{severity} : #{msg}\n"
       end
       @logger.level = Logger::DEBUG
       set :logger, @logger
    end
    
    def self.get_cluster_by_ip(ip)
        cluster='unknown'
        result=DeaList.where(:ip=>ip)
        unless result.empty?
            cluster=result.first.cluster_num
        end
        cluster
    end

    post '/collector/collect_instance_meta' do
     begin
       params = JSON.parse request.body.read
       instance_info={}
       instance_info['state']=params["state"]
       return {:rescode=>-1,:msg=>"instance state is not running"}.to_json unless instance_info['state']=="RUNNING"
       instance_info['time']=Time.now.to_i
       instance_info['host']=params["dea_ip"]
       instance_info['space']=params["tags"]["space_name"]
       instance_info['organization']=params["tags"]["org_name"]
       instance_info['bns_node']=params["tags"]["bns_node"]
       instance_info['app_name']=params["application_name"]
       instance_info['uris']=params["application_uris"].join(",")
       instance_info['instance_index']=params["instance_index"]
       instance_info['cluster_num']=get_cluster_by_ip(instance_info['host'])
       instance_info['warden_handle']=params["warden_handle"]
       instance_info['warden_container_path']=params["warden_container_path"]
       instance_info['state_starting_timestamp']=params["state_starting_timestamp"]
       instance_info['port_info']=params["instance_meta"]["prod_ports"].to_json.to_s
       instance_info['noah_monitor_port']=params["noah_monitor_host_port"]
       instance_info['warden_host_ip']=params["warden_host_ip"]
       instance_info['instance_id']=params["instance_id"]
       instance_info['disk_quota']=params["limits"]["disk"]
       instance_info['mem_quota']=params["limits"]["mem"]
       instance_info['fds_quota']=params["limits"]["fds"]
       InstanceStatus.where(
           :instance_id=>instance_info['instance_id']
       ).first_or_create.update_attributes(instance_info)
       return {:rescode=>0,:msg=>"ok"}.to_json
     rescue => e
         settings.logger.error "#{e.message},#{e.backtrace}"
     end
   end

        post '/collector/collect_instance_resource' do
            begin
            params = JSON.parse request.body.read
            instance_info={}
            instance_info['instance_id']=params["instance_id"]
            instance_info['time']=Time.now.to_i
            instance_info['cpu_usage']=params["usage"]["cpu"]
            instance_info['mem_usage']=params["usage"]["mem"]
            instance_info['fds_usage']=params["usage"]["fds"]
            result=InstanceStatus.where(
                  :instance_id=>instance_info['instance_id']
             )
            if result.empty?
                return {:rescode=>-1,:msg=>"instance doesn't exist"}.to_json
            else
                result.first.update_attributes(instance_info)
                return {:rescode=>0,:msg=>"ok"}.to_json
            end
            rescue => e
                settings.logger.error "#{e.message},#{e.backtrace}"
            end
        end

        get '/collector/instance_existence_check' do
            begin
                instance_id=params["instance_id"]
                if InstanceStatus.where(:instance_id=>instance_id).empty?
                    return {"status"=>"bad"}.to_json
                else
                    return {"status"=>"ok"}.to_json
                end
            rescue => e
                settings.logger.error "#{e.message},#{e.backtrace}"
            end
        end
        post '/collector/collect_dea_info' do
           begin
               params = JSON.parse request.body.read
               dea_info={}
               dea_info["uuid"]=params["uuid"]
               dea_info["ip"]=params["ip"]
               dea_info["cluster_num"]=Cluster.get_cluster_by_ip(dea_info["ip"])
               dea_info["time"]=Time.now.to_i
               DeaList.where(
                    :uuid=>dea_info["uuid"]
                ).first_or_create.update_attributes(dea_info)
               return {:rescode=>0,:msg=>"ok"}.to_json
           rescue => e
               settings.logger.error "#{e.message},#{e.backtrace}"
           end
       end
end
