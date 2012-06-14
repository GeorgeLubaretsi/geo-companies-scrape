#!/usr/bin/env ruby
# encoding: UTF-8
require 'rubygems'
require 'nokogiri'
require 'mechanize'
require 'csv'
require 'json'
require 'logger'
require 'pdf/reader'
require './libSC.rb'
require 'sqlite3'


#Sole entrepreneur 	1
#SPS 			2
#Cooperative 		3
#LTD			4
#Joint Stock Co.	5
#Society limited	6
#non-profit		7
#Legal entity		10
#Foreign enterprise	26
#Foreign non-profit	27
#Business Partnership	28

DB = SQLite3::Database.open "scrapper_db.db"
BASE_URL = "https://enreg.reestri.gov.ge"
HDR = {"X-Requested-With"=>"XMLHttpRequest","cookie"=>"MMR_PUBLIC=7ip3pu3gh4phbaen4f8kpjoi54"}
@br = Mechanize.new { |b|
  b.user_agent_alias = 'Mac Safari'
  b.read_timeout = 1200
  b.max_history=0
  b.retry_change_requests = true
  b.verify_mode = OpenSSL::SSL::VERIFY_NONE
}

@gent = Mechanize.new
@gent.pluggable_parser.pdf = Mechanize::Download

$current_cid

class String
  def pretty
    self.strip.gsub(/\n|\t|\r/,' ').gsub(/\s+/," ").strip
  end
end

class Array
  def pretty
    self.collect{|a| a.strip}
  end
end

def scrape(data,act,rec)
    if act == "list"
      records = Hash.new("")
      Nokogiri::HTML(data).xpath(".//table[@class='main_tbl shadow']/tbody/tr").each{|tr|
        td = tr.xpath("td")
        if td.length < 6
          puts tr.inner_html
          next
        end
        cid = attributes(td[0].xpath("./a"),"onclick").split("(").last.gsub(")","")
        link = BASE_URL + "/main.php?c=app&m=show_legal_person&legal_code_id=#{attributes(td[0].xpath('./a'),'onclick').split('(').last.gsub(')','')}"
        records["link"] = link
        params2 = {"c"=>"app","m"=>"show_legal_person", "legal_code_id"=>cid}

        pg2 = @br.post(BASE_URL + "/main.php",params2,HDR)

        Nokogiri::HTML(pg2.body).xpath(".//table[@class='mytbl']/tbody/tr").each{|tr|
            td2 = tr.xpath("td")
            if td2.length != 2
              #puts tr.inner_html
              next
            end
            col1 = s_text(td2[0].xpath("./text()"))
            col2 = s_text(td2[1])
            if col2 == "" or col2 == " "
              col2 = nil
            end
            records[col1] = col2
            #puts col1 + " =>" + records[col1]

        }
      if(records != nil )
        insert_comp(records)
      else
        next
      end

      Nokogiri::HTML(pg2.body).xpath(".//div[@id='container']/table[caption[text() = 'განცხადებები']]/tbody/tr").each{|tr|
          td3 = tr.xpath("td")
          app_id = attributes(td3[0].xpath("./a"),"onclick").split("(").last.gsub(")","")
          get_add(app_id)
        }

	    puts ":::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"
	}
  end
end


def pdf_parser(file)
	receiver = PDF::Reader::RegisterReceiver.new
	filename = File.expand_path(file)
	PDF::Reader.open(filename) do |reader|
	  reader.pages.each do |page|
	    puts page.text
	  end
	end
end

#this method saves the extract once it is called with appropriate id's,
#calls pdf_parser to read/parse the extract and then removes the file
def get_extract(scandoc_id, app_id)
  ext_param = {"c"=>"mortgage","m"=>"get_output_by_id", "scandoc_id"=>scandoc_id, "app_id"=>app_id}
  @gent.post(BASE_URL + "/main.php",ext_param,HDR).save('./enreg.reestri.gov.ge/temp_extract.pdf')
  #pdf_parser("./enreg.reestri.gov.ge/temp_extract.pdf")
  File.delete("./enreg.reestri.gov.ge/temp_extract.pdf")
end


def action()

  params = {"c"=>"search","m"=>"find_legal_persons","s_legal_person_idnumber"=>"","s_legal_person_name"=>"","s_legal_person_form"=>"3"}

  begin
    pg = @br.post(BASE_URL + "/main.php",params,HDR)
    scrape(pg.body,"list",{})
    next_pg = attributes(Nokogiri::HTML(pg.body).xpath(".//td/a[img[contains(@src,'next.png')]]"),"onclick").scan(/legal_person_paginate\((\d+)\)/).flatten.first
    break if next_pg.nil?
    #break if nex > 5
    #puts nex
    params = {"c"=>"search","m"=>"find_legal_persons","p"=>next_pg}
  end while(true)
end


#goes to the last dead-end page and get the info
def get_add(id)
  
   page_data = Hash.new()
   params3 = {"c"=>"app","m"=>"show_app", "app_id"=> id}
   pg3 = @br.post(BASE_URL + "/main.php",params3,HDR)
   
   Nokogiri::HTML(pg3.body).xpath(".//div[@id='tabs-3']/div/table[caption[text() = 'მომზადებული დოკუმენტები']]/tr").each{|tr|
    rows = tr.xpath('td')
    if(rows.length < 3)
      puts rows
      next
    end
    link = attributes(rows[0].xpath("./a"),"href")
    scandoc_id = CGI.parse(link)['scandoc_id']
    app_id = CGI.parse(link)['app_id']
    dummy = rows[1].xpath("./span")
    text = s_text(dummy[0].xpath("text()"))
    extract_date = s_text(dummy[1].xpath("text()"))
    #puts link + "**" + text + "**" + extract_date
    
    #check whether the document is djvu file, if true, saves the link to the djvu
    if s_text(rows[2]).end_with?(".djvu")
      puts "DEJA VU!!"
      next
    end
    get_extract(scandoc_id, app_id)
   }

    b_number = s_text((Nokogiri::HTML(pg3.body).xpath(".//tr[td[contains(text(), 'რეგისტრაციის ნომერი')]]/td/span[text()]")))
    page_data["b_number"] = b_number
    page_data["property_num"] = id
    page_data["cid"] = $current_cid
    Nokogiri::HTML(pg3.body).xpath(".//div[@id = 'application_tab']/table/tbody/tr").each{|tr|
    row_data = tr.xpath("td")
    if row_data.length != 2
      next
    end
    val1 = s_text(row_data[0])
    val2 = s_text(row_data[1])
    if val2 == "" or val2 == " "
      val2 = nil
    end
    page_data[val1] = val2
   }
   insert_page(page_data)
   if page_data["განმცხადებელი"] != nil
     pid = insert_person(page_data["განმცხადებელი"])
   end
   
   puts "THE NEW PID = #{pid}"
   
end

def insert_page(page_data)
  max_pg_id = DB.execute("SELECT MAX(page_id) FROM pages")
   new_page_id = Integer(max_pg_id[0][0]) + 1
   stm = DB.prepare("SELECT * FROM PAGES WHERE B_number = '#{page_data["b_number"]}'")
   result = stm.execute
   if result.next() == nil
     DB.execute("INSERT INTO pages(cid, page_id, property_num, B_number, entity_name,
          legal_form, reorg_type, number_of, replacement_info, attached_docs, backed_docs, notes)
          VALUES (:cid, :page_id, :property_num, :B_number, :entity_name, :legal_form,
          :reorg_type, :number_of, :replacement_info, :attached_docs, :backed_docs, :notes)",
          "cid" => $current_cid,
          "page_id" => new_page_id,
          "property_num"=> page_data["property_num"],
          "B_number"=> page_data["b_number"],
          "entity_name"=>page_data["სუბიექტის დასახელება"],
          "legal_form"=>page_data["სამართლებრივი ფორმა"],
          "reorg_type" => page_data["რეორგანიზაციის ტიპი"] ,
          "number_of"=> page_data["რაოდენობა"],
          "replacement_info"=>page_data["შესაცვლელი რეკვიზიტი:"],
          "attached_docs"=>page_data["თანდართული დოკუმენტაცია"],
          "backed_docs"=>page_data["გასაცემი დოკუმენტები"],
          "notes"=>page_data["შენიშვნა"])
   else
      result.reset()
      result.each do |row|
        if row[0] != $current_cid or
              row[2] != page_data["property_num"] or
              row[3] != page_data["b_number"] or
              row[4] != page_data["სუბიექტის დასახელება"] or
              row[5] != page_data["სამართლებრივი ფორმა"] or
              row[6] != page_data["რეორგანიზაციის ტიპი"] or
              row[7] != page_data["რაოდენობა"] or
              row[8] != page_data["შესაცვლელი რეკვიზიტი:"] or
              row[9] != page_data["თანდართული დოკუმენტაცია"] or
              row[10] != page_data["გასაცემი დოკუმენტები"] or
              row[11] != page_data["შენიშვნა"]

        puts "CID"
        puts row[0]
        puts $current_cid
        puts "--------------------------------"
        puts row[2]+"!="+ page_data["property_num"]
        puts row[3]+"!="+ page_data["b_number"]

        puts row[4]
        puts page_data["სუბიექტის დასახელება"]
        puts "--------------------------------"
        puts row[5]
        puts page_data["სამართლებრივი ფორმა"]
        puts "--------------------------------"
        puts row[6]
        puts page_data["რეორგანიზაციის ტიპი"]
        puts "--------------------------------"
        puts row[7]
        puts page_data["რაოდენობა"]
        puts "--------------------------------"
        puts row[8]
        puts page_data["შესაცვლელი რეკვიზიტი:"]
        puts "--------------------------------"
        puts row[9]
        puts page_data["თანდართული დოკუმენტაცია"]
        puts "--------------------------------"
        puts row[10]
        puts page_data["გასაცემი დოკუმენტები"]
        puts "--------------------------------"
        puts row[11]
        puts page_data["შენიშვნა"]
            puts "<<<<<<<<<<<<<<<<page ALERT!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
            puts "<<<<<<<<<<<<<<<<page UPDATE!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        else
          puts "SAME PAGE -------------------------->"
        end
      end
   end
end
#insert info about company to the database
#verify if company already in the database(check id_code, p_code, state_reg_code)
#if it is in db verify whether anything different, if different alert, else insert
def insert_comp(data)
  max_row = DB.execute("SELECT MAX(cid) FROM company")
  new_cid = Integer(max_row[0][0]) + 1

  query_qr = "SELECT * FROM COMPANY WHERE "

  #critical section some companies lack all of above fields to be revised for update!! TODO
  if data["საიდენტიფიკაციო კოდი"]== nil and data["პირადი ნომერი"]== nil and
      data["სახელმწიფო რეგისტრაციის ნომერი"] == nil
   
      slct = DB.prepare("SELECT * FROM company WHERE comp_name = ? AND state_reg_date = ?")
      slct.bind_params(data["დასახელება"], data["სახელმწიფო რეგისტრაციის თარიღი"])
      rslt = slct.execute
      rslt.reset()
      if rslt.next() != nil
        rslt.reset()
        puts "CRITICAL IF"
        rslt.each do |row|
          $current_cid = Integer(row[0])
          if row[1] != data["საიდენტიფიკაციო კოდი"] or
                 row[2] != data["პირადი ნომერი"] or
                 row[3] != data["სახელმწიფო რეგისტრაციის ნომერი"] or
                 row[4] != data["დასახელება"] or
                 row[5] != data["სამართლებრივი ფორმა"] or
                 row[6] != data["სახელმწიფო რეგისტრაციის თარიღი"] or
                 row[7] != data["სტატუსი"]

               puts  row[1]+"!="+data["საიდენტიფიკაციო კოდი"]
               puts  row[2]+"!="+data["პირადი ნომერი"]
               puts  row[3]+"!="+data["სახელმწიფო რეგისტრაციის ნომერი"]
               puts  row[4]+"!="+data["დასახელება"]
               puts  row[5]+"!="+ data["სამართლებრივი ფორმა"]
               puts  row[6]+"!="+data["სახელმწიფო რეგისტრაციის თარიღი"]
               puts  row[7]+"!="+data["სტატუსი"]
               puts "<<<<<<<<<<<<<<<<company ALERT!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
               puts "<<<<<<<<<<<<<<<<company UPDATE!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
          else
           puts "<<<<<<<<<<<<<<<<< SAME CRITICAL COMPANY>>>>>>>>>>>>>>>>>>>>>"
          end
        end
      else
         $current_cid = new_cid
        DB.execute("INSERT INTO company(cid, id_code, p_code, state_reg_code, comp_name, legal_form, state_reg_date, status, scrap_date) VALUES (
        :cid, :id_code, :p_code, :state_reg_code, :comp_name, :legal_form, :state_reg_date, :status, :scrap_date)",
          "cid" => $current_cid,
          "id_code"=>data["საიდენტიფიკაციო კოდი"],
          "p_code"=>data["პირადი ნომერი"],
          "state_reg_code"=>data["სახელმწიფო რეგისტრაციის ნომერი"],
          "comp_name"=>data["დასახელება"],
          "legal_form"=>data["სამართლებრივი ფორმა"],
          "state_reg_date"=>data["სახელმწიფო რეგისტრაციის თარიღი"],
          "status"=>data["სტატუსი"],
          "scrap_date"=> Time.now.utc.iso8601)
      end
  end

  if data["საიდენტიფიკაციო კოდი"] != nil
    query_qr = query_qr + " id_code = '#{data["საიდენტიფიკაციო კოდი"]}' "
    id_added = true
    valid_query = true
  end
  if data["პირადი ნომერი"] != nil
    if id_added == true
      query_qr = query_qr + " OR "
    end
    query_qr = query_qr + " p_code = '#{data["პირადი ნომერი"]}' "
    pcode_added = true
    valid_query = true
  end

  if valid_query
    statement = DB.prepare(query_qr)
    result = statement.execute
    if result.next() == nil
      $current_cid = new_cid
      DB.execute("INSERT INTO company(cid, id_code, p_code, state_reg_code, comp_name, legal_form, state_reg_date, status, scrap_date) VALUES (
      :cid, :id_code, :p_code, :state_reg_code, :comp_name, :legal_form, :state_reg_date, :status, :scrap_date)",
        "cid" => $current_cid,
        "id_code"=>data["საიდენტიფიკაციო კოდი"],
        "p_code"=>data["პირადი ნომერი"],
        "state_reg_code"=>data["სახელმწიფო რეგისტრაციის ნომერი"],
        "comp_name"=>data["დასახელება"],
        "legal_form"=>data["სამართლებრივი ფორმა"],
        "state_reg_date"=>data["სახელმწიფო რეგისტრაციის თარიღი"],
        "status"=>data["სტატუსი"],
        "scrap_date"=> Time.now.utc.iso8601)
      
      puts "<<<<<<<<<<<<<<<<<<<<<<<company inserted>>>>>>>>>>>>>>>>>>>>>>>"
    else
      result.reset()
      result.each do |row|
        $current_cid = Integer(row[0])
         if row[1] != data["საიდენტიფიკაციო კოდი"] or
             row[2] != data["პირადი ნომერი"] or
             row[3] != data["სახელმწიფო რეგისტრაციის ნომერი"] or
             row[4] != data["დასახელება"] or
             row[5] != data["სამართლებრივი ფორმა"] or
             row[6] != data["სახელმწიფო რეგისტრაციის თარიღი"] or
             row[7] != data["სტატუსი"]

           puts  row[1]
           puts data["საიდენტიფიკაციო კოდი"]
           puts "))___(("
           puts  row[2]
           puts data["პირადი ნომერი"]
           puts "))___(("
           puts  row[3]
           puts data["სახელმწიფო რეგისტრაციის ნომერი"]
           puts "))___(("
           puts  row[4]
           puts data["დასახელება"]
           puts "))___(("
           puts  row[5]
           puts data["სამართლებრივი ფორმა"]
           puts "))___(("
           puts  row[6]
           puts data["სახელმწიფო რეგისტრაციის თარიღი"]
           puts "))___(("
           puts  row[7]
           puts data["სტატუსი"]
           puts "))___(("
           puts "<<<<<<<<<<<<<<<<company ALERT!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
           puts "<<<<<<<<<<<<<<<<company UPDATE!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
         else
           puts "<<<<<<<<<<<<<<<<<SAME company>>>>>>>>>>>>>>>>>>>>>>>>"
         end
      end
    end
  end
end
  
def insert_person(data_line)
  name = data_line.split(/.*/,1).last.gsub(/\s[(][პ][\/][ნ][:]\s\d*[)].*/, '')
  p_n = data_line.split(/.*[(პ\/ნ:]\s/).last.gsub(/[)].*/, '')
  address = data_line.split(/.*/,1).last.gsub(/.*\d[)]\s/, '')
  slct = DB.prepare("SELECT * FROM people WHERE personal_number = ?")
  slct.bind_params(p_n)
  rslt = slct.execute
  max_row = DB.execute("SELECT MAX(pid) FROM people")
  new_pid = Integer(max_row[0][0]) + 1
  if rslt.next() == nil
    DB.execute("INSERT INTO people(pid, name, address, personal_number) VALUES(:pid, :name, :address, :personal_number)",
      "pid"=>new_pid,
      "name"=>name,
      "address"=>address,
      "personal_number"=>p_n)
      pid = new_pid
  else
    puts "THE P/N IS ALREADY in the DATABASE"
    rslt.reset()
    rslt.each do |row|
     pid = Integer(row[0])
    end
  end
  pid
end

action()

