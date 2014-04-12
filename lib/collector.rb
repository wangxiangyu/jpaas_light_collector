require 'sinatra/base'
require 'mysql'
require 'json'
require "yaml"
require "logger"


class Collector < Sinatra::Base
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
           @config["mysql"]["port"]||=3306
           @mysql_conn||=Mysql.real_connect(@config["mysql"]["host"],@config["mysql"]["username"],@config["mysql"]["password"],@config["mysql"]["db_name"],@config["mysql"]["port"])
           set :mysql_conn, @mysql_conn
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
    post '/collector/collect_instance_meta' do
     begin
       params = JSON.parse request.body.read
       instance_info={}
       instance_info['state']=params["state"]
       return {:rescode=>-1,:msg=>"instance state is not running"}.to_json unless instance_info['state']=="RUNNING"
       instance_info['time']=Time.now.to_i
       instance_info['host']="0.0.0.0"
       instance_info['space']=params["tags"]["space_name"]
       instance_info['organization']=params["tags"]["org_name"]
       instance_info['bns_node']=params["tags"]["bns_node"]
       instance_info['app_name']=params["application_name"]
       instance_info['uris']=params["application_uris"].join(",")
       instance_info['instance_index']=params["instance_index"]
       instance_info['cluster_num']="unknown"
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
       if settings.mysql_conn.query("select * from instance_status where  instance_id='#{instance_info['instance_id']}'").fetch_hash.nil?
           settings.mysql_conn.query("insert into instance_status set time='#{instance_info['time']}',host='#{instance_info['host']}',app_name='#{instance_info['app_name']}',instance_index='#{instance_info['instance_index']}',cluster_num='#{instance_info['cluster_num']}',organization='#{instance_info['organization']}',space='#{instance_info['space']}',bns_node='#{instance_info['bns_node']}',uris='#{instance_info['uris']}',state='#{instance_info['state']}',warden_handle='#{instance_info['warden_handle']}',warden_container_path='#{instance_info['warden_container_path']}',state_starting_timestamp='#{instance_info['state_starting_timestamp']}',port_info='#{instance_info['port_info']}',noah_monitor_port='#{instance_info['noah_monitor_port']}',warden_host_ip='#{instance_info['warden_host_ip']}',instance_id='#{instance_info['instance_id']}',disk_quota='#{instance_info['disk_quota']}',mem_quota='#{instance_info['mem_quota']}',fds_quota='#{instance_info['fds_quota']}'")
       else
           settings.mysql_conn.query("update instance_status set time='#{instance_info['time']}',host='#{instance_info['host']}',app_name='#{instance_info['app_name']}',instance_index='#{instance_info['instance_index']}',cluster_num='#{instance_info['cluster_num']}',organization='#{instance_info['organization']}',space='#{instance_info['space']}',bns_node='#{instance_info['bns_node']}',uris='#{instance_info['uris']}',state='#{instance_info['state']}',warden_handle='#{instance_info['warden_handle']}',warden_container_path='#{instance_info['warden_container_path']}',state_starting_timestamp='#{instance_info['state_starting_timestamp']}',port_info='#{instance_info['port_info']}',noah_monitor_port='#{instance_info['noah_monitor_port']}',warden_host_ip='#{instance_info['warden_host_ip']}',disk_quota='#{instance_info['disk_quota']}',mem_quota='#{instance_info['mem_quota']}',fds_quota='#{instance_info['fds_quota']}' where instance_id='#{instance_info['instance_id']}'")
        end
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
            if settings.mysql_conn.query("select * from instance_status where  instance_id='#{instance_info['instance_id']}'").fetch_hash.nil?
                return {:rescode=>-1,:msg=>"instance doesn't exist"}.to_json
            else
                settings.mysql_conn.query("update instance_status set cpu_usage='#{instance_info['cpu_usage']}',mem_usage='#{instance_info['mem_usage']}',fds_usage='#{instance_info['fds_usage']}',time='#{instance_info['time']}' where instance_id='#{instance_info['instance_id']}'")
                return {:rescode=>0,:msg=>"ok"}.to_json
            end
            rescue => e
                settings.logger.error "#{e.message},#{e.backtrace}"
            end
        end

        get '/collector/instance_existence_check' do
            begin
                instance_id=params["instance_id"]
                if settings.mysql_conn.query("select * from instance_status where  instance_id='#{instance_id}'").fetch_hash.nil?
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
               dea_info["cluster_num"]="unknown"
               dea_info["time"]=Time.now.to_i
               if settings.mysql_conn.query("select * from dea_list where  uuid='#{dea_info['uuid']}'").fetch_hash.nil?
                   settings.mysql_conn.query("insert into dea_list set uuid='#{dea_info["uuid"]}',ip='#{dea_info["ip"]}',cluster_num='#{dea_info["cluster_num"]}',time='#{dea_info["time"]}'")
               else
                    settings.mysql_conn.query("update dea_list set time='#{dea_info["time"]}' where uuid='#{dea_info['uuid']}'")
               end
               return {:rescode=>0,:msg=>"ok"}.to_json
           rescue => e
               settings.logger.error "#{e.message},#{e.backtrace}"
           end
       end
end
