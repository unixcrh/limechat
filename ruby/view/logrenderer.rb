# Created by Satoshi Nakagawa.
# You can redistribute it and/or modify it under the Ruby's license or the GPL2.

module LogRenderer
  class << self
    
    def render_body(body, keywords, dislike_words, whole_line)
      effects, body = process_effects(body)
      urls = process_urls(body)
      keywords = process_keywords(body, urls, keywords, dislike_words)
      
      if whole_line && !keywords.empty?
        addrs = []
        keywords = []
        
        if urls.empty?
          keywords << { :pos => 0, :len => body.size }
        else
          # build keywords to cover the rest parts of the urls
          start = 0
          urls.each do |u|
            len = u[:pos] - start
            keywords << { :pos => start, :len => len } if len > 0
            start = u[:pos] + u[:len]
          end
          if start < body.size
            keywords << { :pos => start, :len => body.size - start }
          end
        end
      else
        addrs = process_addresses(body)
        addrs.delete_if {|a| urls.find {|u| intersect?(a,u)}} unless urls.empty?
        addrs.delete_if {|a| keywords.find {|k| intersect?(a,k)}} unless keywords.empty?
      end
      events = combine_events(effects, urls, addrs, keywords)
      
      if events.empty?
        body = escape_str(body)
        return [body, false]
      end

      effect = nil
      url = nil
      addr = nil
      key = nil
      pending_effect = nil
    
      s = ''
      pos = 0
      body.each_char do |c|
        evs = events.select {|i| i[:pos] == pos}
        unless evs.empty?
          t = ''
          evs.each do |e|
            case e[:kind]
            when :effect
              if url || key
                pending_effect = e[:off] ? nil : e
              else
                if e[:off]
                  effect = nil
                  t += render_end_tag(:effect)
                else
                  t += render_end_tag(:effect) if effect
                  effect = e
                  t += render_start_tag(e)
                end
              end
            when :urlend
              if url
                url = nil
                t += render_end_tag(:url)
              end
              if !effect && pending_effect
                effect = pending_effect
                pending_effect = nil
                t += render_start_tag(effect)
              end
            when :addrend
              if addr
                addr = nil
                t += render_end_tag(:address)
              end
              if !effect && pending_effect
                effect = pending_effect
                pending_effect = nil
                t += render_start_tag(effect)
              end
            when :keyend
              if key
                key = nil
                t += render_end_tag(:key)
              end
              if !effect && pending_effect
                effect = pending_effect
                pending_effect = nil
                t += render_start_tag(effect)
              end
            when :urlstart
              if effect
                pending_effect = effect
                effect = nil
                t += render_end_tag(:effect)
              end
              t += render_end_tag(:url) if url
              url = e
              t += render_start_tag(e)
            when :addrstart
              if effect
                pending_effect = effect
                effect = nil
                t += render_end_tag(:effect)
              end
              t += render_end_tag(:address) if addr
              addr = e
              t += render_start_tag(e)
            when :keystart
              if effect
                pending_effect = effect
                effect = nil
                t += render_end_tag(:effect)
              end
              t += render_end_tag(:key) if key
              key = e
              t += render_start_tag(e)
            end
          end
          s += t
        end
        
        pos += c.size
        s += escape_char(c)
      end
    
      s += render_end_tag(:url) if url
      s += render_end_tag(:key) if key
      s += render_end_tag(:effect) if effect
      [s, !keywords.empty?]
    end
    
    
    private
    
    def escape_str(s)
      a = ''
      prev = nil
      s.each_char do |c|
        if c == ' ' && prev == ' '
          a += '&nbsp;'
          prev = nil
          next
        end
        prev = c
        a += escape_char(c)
      end
      a
    end
    
    def escape_char(c)
      case c
      when '<'; '&lt;'
      when '>'; '&gt;'
      when '&'; '&amp;'
      when '"'; '&quot;'
      when "\t"; '&nbsp;&nbsp;&nbsp;&nbsp;'
      else c
      end
    end
    
    COLOR_MAP = {
       0 => '#fff',
       1 => '#000',
       2 => '#008',
       3 => '#080',
       4 => '#f00',
       5 => '#800',
       6 => '#808',
       7 => '#f80',
       8 => '#ff0',
       9 => '#0f0',
      10 => '#088',
      11 => '#0ff',
      12 => '#00f',
      13 => '#f0f',
      14 => '#888',
      15 => '#ccc',
    }
    
    def num_to_color(n)
      COLOR_MAP[n%16]
    end
    
    def render_start_tag(e)
      case e[:kind]
      when :urlstart
        %Q[<a class="url" href="#{e[:url]}" oncontextmenu="on_url_contextmenu()">]
=begin
        url = e[:url]
        if /^http:\/\/[a-z]+\.youtube\.com\/watch\?v=([a-zA-Z0-9]+)$/ =~ url
          id = $1
          %Q[<object width="425" height="350"><param name="movie" value="#{url}"></param><param name="wmode" value="transparent"></param><embed src="http://www.youtube.com/v/#{id}" type="application/x-shockwave-flash" wmode="transparent" width="425" height="350"></embed></object>]
        elsif /\.(jpg|jpeg|gif|png)$/ =~ url
          %Q[<a class="url" href="#{e[:url]}" oncontextmenu="on_url_contextmenu()"><img src="#{url}"/>]
        else
          %Q[<a class="url" href="#{e[:url]}" oncontextmenu="on_url_contextmenu()">]
        end
=end
      when :addrstart; '<span class="address" oncontextmenu="on_address_contextmenu()">'
      when :keystart; '<strong class="highlight">'
      when :effect
        s = '<span class="effect" style="'
        s += 'font-weight:bold;' if e[:bold]
        s += 'text-decoration:underline;' if e[:underline]
        s += 'font-style:italic;' if e[:reverse]
      
        text = e[:text]
        if text
          text = num_to_color(text)
          s += "color:#{text};"
        end
      
        back = e[:back]
        if back
          back = num_to_color(back)
          s += "background-color:#{back};"
        end
      
        s += '">'
        s
      end
    end
  
    def render_end_tag(kind)
      case kind
      when :url; '</a>'
      when :address; '</span>'
      when :key; '</strong>'
      when :effect; '</span>'
      end
    end

    def process_effects(body)
      effects = []
      s = body.dup
      b = ''
      offset = 0
      n = 0
      while /[\x02\x0f\x16\x1f]|\x03((\d{1,2})(,(\d{1,2}))?)?/ =~ s
        left = $~.begin(0)
        right = $~.end(0)
        t = s[left...right]
        pos = offset + left
        case t[0]
        when 0x02; effects << { :type => :bold, :pos => pos }
        when 0x0f; effects << { :type => :stop, :pos => pos }
        when 0x1f; effects << { :type => :underline, :pos => pos }
        when 0x16; effects << { :type => :reverse, :pos => pos }
        when 0x03
          text = $1
          text = text.to_i if text
          back = $4
          back = back.to_i if back
          effects << { :type => :color, :pos => pos, :serial => n, :text => text, :back => back }
        end
        b += s[0...left]
        s[0...right] = ''
        offset += left
        n += 1
      end
      body = b + s
      return [[], body] if effects.empty?
    
      bold = underline = reverse = false
      text = back = nil
    
      hash = {}
      effects.each do |i|
        case i[:type]
        when :bold; bold = !bold
        when :underline; underline = !underline
        when :reverse; reverse = !reverse
        when :stop
          next if !bold && !underline && !reverse && !text && !back
          bold = underline = reverse = false
          text = back = nil 
        when :color
          next if text == i[:text] && back == i[:back]
          text = i[:text]
          back = i[:back]
        end
        off = !bold && !underline && !reverse && !text && !back
        hash[i[:pos]] = { :pos => i[:pos], :serial => i[:serial], :bold => bold, :underline => underline, :reverse => reverse, :text => text, :back => back, :off => off }
      end
      effects = hash.keys.sort.map {|k| hash[k]}
    
      [effects, body]
    end
  
    #URL_REGEX = /(?:h?ttps?|ftp):\/\/[-_a-zA-Z\d.!~*':@%]+(?:\/[-_a-zA-Z\d.!~*'%;\/?:@&=+$,#()]*)?/
    #URL_REGEX = /(?:h?ttps?|ftp):\/\/[-_a-zA-Z\d.!~*':@%]+(?:\/[-_a-zA-Z\d.!~*'%;\/?:@&=+$,#()¡-⿻、-힣-￿]*)?/
    
    URL_REGEX = /(?:h?ttps?|ftp):\/\/[^\s　]+/
  	ADDRESS_REGEX = /(?:[a-zA-Z\d](?:[-a-zA-Z\d]*[a-zA-Z\d])?\.)(?:[a-zA-Z\d](?:[-a-zA-Z\d]*[a-zA-Z\d])?\.)+[a-zA-Z]{2,6}|(?:[a-f\d]{0,4}:){7}[a-f\d]{0,4}|(?:\d{1,3}\.){3}[\d]{1,3}/
    
    def process_urls(body)
      urls = []
      s = body.dup
      offset = 0
      while URL_REGEX =~ s
        left = $~.begin(0)
        right = $~.end(0)
        url = s[left...right]
        url = 'h' + url if /^ttp/ =~ url
        urls << { :url => url, :pos => offset+left, :len => right-left }
        s[0...right] = ''
        offset += right
      end
      urls
    end
    
    def process_addresses(body)
      addrs = []
      s = body.dup
      offset = 0
      while ADDRESS_REGEX =~ s
        left = $~.begin(0)
        right = $~.end(0)
        addr = s[left...right]
        addrs << { :address => addr, :pos => offset+left, :len => right-left }
        s[0...right] = ''
        offset += right
      end
      addrs
    end
  
    def intersect?(a, b)
      al = a[:pos]
      ar = al + a[:len]
      bl = b[:pos]
      br = bl + b[:len]
      al <= bl && bl < ar || al < br && br <= ar || bl <= al && al < br || bl < ar && ar <= br
    end
  
    def process_keywords(body, urls, words, dislike_words)
      return [] unless words && !words.empty?
      
      keywords = []
      words.each do |w|
        next if w.empty?
        s = body.dup
        offset = 0
        rex = Regexp.new(Regexp.escape(w), true)
        while rex =~ s
          left = $~.begin(0)
          right = $~.end(0)
          keywords << { :pos => offset+left, :len => right-left }
          s[0...right] = ''
          offset += right
        end
      end
      
      return [] if keywords.empty?
      keywords.sort! {|a,b| a[:pos] <=> b[:pos] }
      
      # eliminate keywords intersect one of urls
      keywords.delete_if {|k| urls.find {|u| intersect?(k,u)}} unless urls.empty?
      
      if dislike_words && !dislike_words.empty?
        dislike_matches = []
        dislike_words.each do |w|
          next if w.empty?
          s = body.dup
          offset = 0
          rex = Regexp.new(Regexp.escape(w), true)
          while rex =~ s
            left = $~.begin(0)
            right = $~.end(0)
            dislike_matches << { :pos => offset+left, :len => right-left }
            s[0...right] = ''
            offset += right
          end
        end
        # eliminate keywords intersect one of dislike_words
        keywords.delete_if {|k| dislike_matches.find {|u| intersect?(k,u)}} unless dislike_matches.empty?
      end
      
      # combine keyword ranges
      
      new_keywords = []
      i = 0
      while i < keywords.size
        k = keywords[i]
        loop do
          n = keywords[i+1]
          unless n
            new_keywords << k
            break
          end
          if k[:pos] + k[:len] >= n[:pos]
            k[:len] += n[:len] - (k[:pos] + k[:len] - n[:pos])
            i += 1
          else
            new_keywords << k
            break
          end
        end
        i += 1
      end
      new_keywords
    end
  
    def combine_events(effects, urls, addrs, keywords)
      events = []
      events += effects.map {|i| i[:kind] = :effect; i }
      urls.each do |i|
        s = i.dup
        s[:kind] = :urlstart
        events << s
        s = i.dup
        s[:kind] = :urlend
        s[:pos] += s[:len]
        events << s
      end
    
      addrs.each do |i|
        s = i.dup
        s[:kind] = :addrstart
        events << s
        s = i.dup
        s[:kind] = :addrend
        s[:pos] += s[:len]
        events << s
      end
    
      keywords.each do |i|
        s = i.dup
        s[:kind] = :keystart
        events << s
        s = i.dup
        s[:kind] = :keyend
        s[:pos] += s[:len]
        events << s
      end
      
      # sort:
      #   effect off < urlend == keyend == addrend < urlstart == keystart == addrstart < effect on
      #
      events.sort! do |a,b|
        cond = a[:pos] <=> b[:pos]
        if cond == 0
          if a[:kind] == b[:kind]
            if a[:kind] == :effect
              a[:serial] <=> b[:serial]
            else
              0
            end
          else
            x = a[:kind]
            y = b[:kind]
            if x == :effect && a[:off]
              -1
            elsif x == :effect && !a[:off]
              1
            elsif y == :effect && b[:off]
              1
            elsif y == :effect && !b[:off]
              -1
            elsif x == :urlend || x == :keyend || x == :addrend
              -1
            else
              1
            end
          end
        else
          cond
        end
      end
      
      events
    end
  end
end
