###########################################################################################
###
### 名古屋帯：bigramを用いた日本語テキストの難易度推定
### NagoyaObi: readability accessment of Japanese texts based on character-bigram models
### 
### Copyright (c) Satoshi Sato, 2009
###
### License: Creative Commons 3.0, Attribution-Noncommercial-Share Alike.
###
###########################################################################################

require_relative 'matrix'
require 'nkf'

###
### Arrayクラスの拡張
### 
class Array
  def max_index
    max = self[0]; index = 0
    self.each_with_index do |o, i|
      if o > max 
        max = o; index = i
      end
    end
    index
  end

  def sum
    self.inject(0) { |sum, i| sum+i }
  end

  def median
    if (self.length % 2) != 0
      self[self.length/2]
    else
      m = self.length/2
      (self[m-1]+self[m])/2
    end
  end

  def m_average
    self[1, self.size-2].average
  end

  def average
    self.sum.to_f/self.size
  end

  def each_line(&pobj)
    self.each(&pobj)
  end

end

###
### Regression （K次多項式による回帰）
###
module Regression

  module_function

  def regression(k, y, x)
    x ||= Array.new(y.length) { |i| i.to_f }
    regression_values(regression_parameters(k, y, x), x)
  end

  def regression_parameters(k, y, x)
    n = y.length
  
    a_inv = Matrix.rows((0 .. k).map do |j|
                          (0 .. k).map do |l|
                            (0 .. n-1).inject(0.0) { |sum, i| sum + x[i]**(j+l) }
                          end
                        end).inverse
    b = Matrix.column_vector((0 .. k).map do |j|
                               (0 .. n-1).inject(0.0) { |sum, i| sum + y[i] * x[i]**j }
                             end)
    c = a_inv * b

    (0 .. k).map { |i| c[i,0] }
  end

  def regression_values(p, xs)
    xs.map do |x|
      regression_value(p, x)
    end
  end

  def regression_value(p, x)
    (0 .. p.length-1).inject(0) do |sum, i|
      sum += p[i] * x ** i
    end
  end

end

###
### NagoyaObi: 難易度判定用クラス
###
module NagoyaObi

  @@N         = 2        ## unigramの場合は1
  @@KanjiCode = nil      ## 変換なし (nil | S | E | J )

  module_function

  def version
    "NagoyaObi 2.305 (2009-08-12) Copyright 2009, Satoshi Sato"
  end

  def default_kanji_code(val)
    @@KanjiCode = val
  end

  def use_unigram
    @@N = 1
    self.use_3_median
  end

  def use_bigram
    @@N = 2
    self.use_3_median
#    self.use_5_median
  end

  ###
  ### 有効文字定義ファイルのロード／有効bigramチェック
  ###
  def load_operative_character_file(file)	# 漢字コードは UTF8
    operative = Hash.new
    IO.foreach(file) do |line|
      line.chomp!
      operative[line.split(/\t/)[0]] = true
    end
    operative
  end

  def operative?(bigram, operative)
    bigram.split(//).each do |c|
      return nil unless operative[c]
    end
    bigram
  end

  ###
  ### 漢字コード (E, J, S, W)
  ### 
  def kanji_code(spec, kanji_code=nil)
    if spec && spec == 'W'
      nil                                   # 変換なし
    elsif spec && ( spec =~ /^[EJS]$/ )   # W16は、正しく動作しない！
      spec                                  # 変換あり
    elsif spec 
      raise "#{spec} is not a valid kanji specification!"
    elsif kanji_code
      kanji_code
    elsif @@KanjiCode 
      @@KanjiCode                           # デフォールト
    else
      nil
    end
  end

  ###
  ### Bigramの取得
  ### 
  def bigram_from_io(io, kanji_code=nil)
    c = []
    io.each_line do |line|
      line = kanji_code ? NKF.nkf("-#{kanji_code}w", line) : line
      line.chomp!

      # 前の行との接続
      if line =~ /^\s*$/ or line =~ /^</ # 空行または行頭がタグの場合、連続させない！
        c = []
      end

      # テキストの整形
      tail_tag = ( line =~ />$/ ? true : false ) # 行末がタグかどうか
      line.gsub!(/<[^<]*>/, '')	         # タグを削除（行中のタグは、ないものと考える）
      line.gsub!(/\s/, '')               # 半角スペースとタブは削除する

      # bigramの作成
      c += line.split(//)
      (c.length-1).times do
        b = c[0, 2].join('')
        yield(b)
        c.shift
      end

      if tail_tag                 # 行末がタグの場合は、次の行とは連続させない！
        c = [] 
      end
    end

  end

  def operative_bigram_from_io(io, kanji_code, op_char)
    bigram_from_io(io, kanji_code) do |b|
      if new = operative?(b, op_char)
        yield(new)
      end
    end
  end

  ###
  ### Unigramの取得
  ### 
  def unigram_from_io(io, kanji_code=nil)
    io.each_line do |line|
      line = kanji_code ? NKF.nkf("-#{kanji_code}w", line) : line
      line.chomp!

      # テキストの整形
      line.gsub!(/<[^<]*>/, '')	         # タグを削除（行中のタグは、ないものと考える）
      line.gsub!(/\s/, '')               # 半角スペースとタブは削除する

      # Unigramの作成
      line.split(//).each do |c|
        yield(c)
      end
    end
  end

  def operative_unigram_from_io(io, kanji_code, op_char)
    unigram_from_io(io, kanji_code) do |c|
      yield(c) if op_char[c]
    end
  end

  ###
  ### n-gram
  ###
  def operative_ngram_from_io(io, kanji_code, op_char, n=@@N)
    if n == 1
      if op_char 
        unigram_from_io(io, kanji_code) do |c|
          yield(c) if op_char[c]
        end
      else
        unigram_from_io(io, kanji_code) do |c|
          yield(c)
        end
      end
    else
      bigram_from_io(io, kanji_code) do |b|
        if new = operative?(b, op_char)
          yield(new)
        end
      end
    end
  end

  ###
  ### コーパス定義ファイルのロード
  ###
  def load_corpus_definition(file)
    definition = []
    IO.foreach(file) do |line|
      line.chomp!
      definition << line.split(/\t/)    # file_spec \t kanji \t grade \t info ...
    end
    definition
  end
  
  ###
  ### コーパスのロード／作成
  ###
  def load_corpus(corpus_dir, definition, operative, kanji_code=nil)
    corpus = Hash.new
    grades = 0               # 難易度のグレード数：グレードは、必ず 1 .. grades

    # ファイルのロード
    definition.each do |d|
      grade = d[2].to_i
      File.open([corpus_dir, d[0]].join("/")) do |io|
    #        STDERR.print "."
        operative_ngram_from_io(io, kanji_code(d[1], kanji_code), operative) do |b|
          corpus[b] ||= []
          corpus[b][grade] ? corpus[b][grade] += 1 : corpus[b][grade] = 1
        end
      end
      grades = grade if grade > grades
    end
    load_corpus_sub(corpus, grades)
  end

  def load_corpus_sub(corpus, grades)
    # corpusを完全な形に： nilを頻度0に；先頭要素(idx=0)は総数
    corpus.each_key do |k|
      corpus[k] += Array.new(grades+1-(corpus[k].length))  # 末尾の不足要素を充足
      corpus[k] = corpus[k].collect{|x| x || 0}            # nil → 0
      corpus[k][0] = corpus[k].inject(0){|sum, x| sum+x}   # 先頭に総数を
    end
    corpus
  end

  def load_partition_corpus(corpus_dir, partition, p, operative, kanji_code=nil)
    corpus = Hash.new
    grades = 0               # 難易度のグレード数：グレードは、必ず 1 .. grades

    # ファイルのロード
    (0 ... partition.length).each do |i|
      next if i == p                 # p-partitionはロードしない！
      partition[i].each do |d|
        grade = d[2].to_i
        File.open([corpus_dir, d[0]].join("/")) do |io|
          operative_ngram_from_io(io, kanji_code(d[1], kanji_code), operative) do |b|
            corpus[b] ||= []
            corpus[b][grade] ? corpus[b][grade] += 1 : corpus[b][grade] = 1
          end
        end
        grades = grade if grade > grades
      end
    end
    load_corpus_sub(corpus, grades)
  end

  # コーパスのコピー
  def copy_corpus(corpus)
    cp = Hash.new
    corpus.each_key do |k|
      cp[k] = corpus[k].dup
    end
    cp
  end
  
  # leave_one_out用のコーパスを作成
  def make_corpus_for_leave_one_out(corpus, text, grade)
    cp = copy_corpus(corpus)        # コピー
    text.each_key do |k|
      if cp[k]
        cp[k][grade] -= text[k][0]  # 対応するグレードの頻度を減算
        cp[k][0]     -= text[k][0]  # 総数を減算
      end
    end
    cp
  end
  
  ###
  ### コーパス定義ファイルとコーパスのロード
  ### 
  def load_corpus_from_def(corpus_def, corpus_dir, op_char, kanji_code=nil)

    #     # Step 0: 有効文字定義ファイルをロードする
    #     op_char = load_operative_character_file(op_char_def)
    # Step 1: コーパス定義ファイルをロードする
    definition = load_corpus_definition(corpus_def)
    # Step 2: コーパスをロードする
    corpus = load_corpus(corpus_dir, definition, op_char, kanji_code)

    [corpus, definition]
  end

  ###
  ### コーパスサイズ
  ### 
  def corpus_size(corpus_def, corpus_dir, op_char=nil)

    # Step 1: コーパス定義ファイルをロードする
    definition = load_corpus_definition(corpus_def)
    # Step 2: コーパスをロードする
    @@N = 1 unless op_char
    corpus = load_corpus(corpus_dir, definition, op_char)

    all = nil
    corpus.each_key do |k|
      all = add_list(all, corpus[k])
    end

    print all.join(" "), "\n"
  end

  ###
  ### テキストのロード
  ### 
  def load_text(io_spec, kanji_code_spec, op_char)
    text = Hash.new
    kanji_code = kanji_code(kanji_code_spec)

    if io_spec.class == IO or io_spec.class == Array
      operative_ngram_from_io(io_spec, kanji_code, op_char) do |b|
        text[b] ||= [0]
        text[b][0] += 1
      end
    elsif io_spec.class == String
      if File.readable?(io_spec) 
        File.open(io_spec) do |io|
          operative_ngram_from_io(io, kanji_code, op_char) do |b|
            text[b] ||= [0]
            text[b][0] += 1
          end
        end
      else
        abort("cannot open file:#{io_spec}")
      end
    end
    
    text
  end
  
  ###
  ### モデルの作成
  ###
  def make_model(corpus, required_frequency)
    
    # 頻度が足りないbigramを削除する
    if required_frequency > 0
      corpus.each_key do |k|
        corpus.delete(k) unless corpus[k][0] >= required_frequency
      end	
    end
    
    total = make_total(corpus)

    model = Hash.new
    corpus.each_key do |k|
      f = k.split(//)[0]  # 先頭文字
      model[k] = make_model_sub(corpus[k], total[f])
    end
    
    NagoyaObi::Model.new(model)
  end
  
  def make_total(corpus)
    if @@N == 1
      make_total_unigram(corpus)
    else
      make_total_bigram(corpus)
    end
  end

  def make_total_bigram(corpus)
    total = Hash.new
    corpus.each_key do |k|
      f = k.split(//)[0]  # 先頭文字
      total[f] = add_list(total[f], corpus[k])
    end
    total
  end

  def make_total_unigram(corpus)
    all = nil
    corpus.each_key do |k|
      all = add_list(all, corpus[k])
    end

    total = Hash.new
    corpus.each_key do |k|
      total[k] = all
    end
    total
  end
  
  def add_list(sum, add)
    if sum
      (0...sum.length).each do |i|
        sum[i] += add[i]
      end
      sum
    else
      add.dup
    end
  end
  
  ## あるbigramに対する正規化されたlikelihoodを計算する
  def make_model_sub(f, total)
    # 確率計算
    p = [f[0]]
    (1...f.length).each do |i|
      p[i] = ( f[i] == 0 ? 0.0 : f[i].to_f/total[i] )
    end
    
    # 線形補間（確率0をなくす）
    p = interpolate(p)	 
     
     # log確率に変換
    w = []
    (1...p.length).each do |i|
      w[i-1] = log10(p[i])
    end
    
    # 平均からの差
    average = w.inject(0.0){|s,x| s+x}/w.length
    (0...w.length).each do |i|
      w[i] = w[i] - average 
    end
    
    # 出現頻度
    w.unshift(f[0])		    # 先頭はfからコピー
    w
  end
  
  # 線形補間
  def interpolate(f)
    v = f.collect{|x| x.to_f}       # 小数に変換
    v.shift                         # 先頭(総数)を捨てる
    zeros = v.collect{|x| x == 0.0}
    while zeros.find{|x| x} do
      #    print v.join(" "), "\n"
      v = interpolate_sub(v, zeros)
      zeros = v.collect{|x| x == 0.0}
    end
    v.unshift(f[0])		  # 先頭はfからコピー(オリジナルの出現頻度)
  end
  
  def interpolate_sub(v, zeros)
    new = []
    (0...v.length).each do |i|
      new[i] = 
        if zeros[i]
          if i == 0
            v[i+1]/2
          elsif i == v.length-1
            v[i-1]/2
          else
            (v[i-1]+v[i+1])/2
          end
        else
          v[i]
        end
    end
    new
  end
  
  def log10(x)
    Math.log(x)/Math.log(10.0)
  end
  
  ###
  ### モデルのロード
  ###
  def load_model(model_spec, model_dir, required_frequency)
    load_model_file(make_model_filename(model_spec, model_dir), required_frequency,
                    model_spec)
  end

  def load_model_file(file, required_frequency, model_spec=nil)
    model = Hash.new
    IO.foreach(file) do |line|
      line.chomp!
      x = line.split(/\t/)
      if x[1].to_i >= required_frequency
        model[x.shift] = [x.shift.to_i] + x.collect{|v| v.to_f}
      end
    end
    NagoyaObi::Model.new(model, model_spec)
  end
  
  def make_model_filename(name, dir)
    if name == 'T7'
      "#{dir}/Obi2-T13.model"
    else
      "#{dir}/Obi2-#{name}.model"
    end
  end
  
  class Model
    
    def initialize(model, spec=nil)
      @model_spec  = spec || nil
      @model = model
    end

    ### モデルのセーブ
    def save_model(model_output)
      open(model_output, "w") do |f|
        @model.each_key do |k|
      #          out = [k] + @model[k]
          out = [k] + [@model[k][0]] + @model[k][1..-1].collect{|x| sprintf("%.5f", x)}
          f.print out.join("\t"), "\n"
        end
      end
    end

    ###
    ### 難易度の推定
    ### 
    def readability(io_spec, kanji_code_spec, op_char, smoothing=nil)
      self.readability0(NagoyaObi.load_text(io_spec, kanji_code_spec, op_char),
                        smoothing)
    end

    def readability0(text, smoothing=nil)
      NagoyaObi::Result.new(text, calculate_likelihoods(text), @model_spec, smoothing)
    end

    def calculate_likelihoods(text)
      total = [0]
      text.each_key do |k|
        if @model[k] 
          total[0] += text[k][0]
          (1...@model[k].length).each do |i|
            total[i] ||= 0.0
            total[i] += (text[k][i] = text[k][0] * @model[k][i])
          end
        else
          text.delete(k)	# 有効bigramではない！
        end
      end
      total
    end
  
  end

  class Result

    MethodList = ['ns', 's5', 's4', 's3', 's2']
    VotingList = ['ns', 's4', 's2']

    def initialize(text, contrib, model_spec=nil, smoothing=nil)
      @text = text
      @contrib = contrib
      @voting_list = VotingList
      @estimat = make_estimation(@contrib)
      if smoothing
        self.set_voting_list(smoothing.collect{|v| v == 0 ? 'ns' : "s#{v}"})
      end
      if model_spec == 'T7'
        @final   = final_estimation(@estimat).collect{|x| t7_scale_transform(x)}
      else
        @final   = final_estimation(@estimat)
      end
    end

    def set_voting_list(list)
      @voting_list = list
    end

    def make_estimation(contrib)
      estimat = Hash.new
    
      if (operative_len = contrib[0]) > 0 
        estimat['ns'] = contrib[1 .. -1].map{|x| 100 * x / operative_len }  # 100bigram当たりの値
        #        estimat['ns'] = contrib[1 .. -1].map{|x| x}
        [2,3,4,5].each do |i|
          estimat["s#{i}"] = Regression.regression(i, estimat['ns'], nil)
        end
      end
    
      estimat
    end
  
    def final_estimation(estimat)
      if estimat.size > 0       ## Normal Case
        list = MethodList.map{|x| estimat[x].max_index + 1}
        [ @voting_list.map{|x| estimat[x].max_index + 1}.sort.median ] + list
      else                      ## Exception (No operative characters)
        (0 .. MethodList.size).collect { |x| 0 }
      end
    end

    def grade(t7=nil)
      if t7
        t7_scale_transform(@final[0])
      else
        @final[0]
      end
    end

    def t7_scale_transform(val)
      if val == 0
        0
      elsif val <= 6
        1
      elsif val == 13
        7
      elsif 11 <= val and val <= 12
        6
      else
        val - 5
      end
    end

    def show(info=[], param={})
      separator = param['separator'] || ' '

      if param['contrib']
        @text.each_key do |k|
          c = @text[k]
          c[0] = sprintf("%3d", c[0])
          c[1..-1] = c[1..-1].collect{|x| sprintf("%6.2f", x)}
          c.unshift(k)
          print c.join(" "), "\n"
        end
        print "\n"
      end

      if param['likelihood']
        MethodList.each do |v|
          print [v, sprintf("%2d", @estimat[v].max_index+1), 
                 @estimat[v].map{|x| sprintf("%6.2f", x)}.join(" ")].join(" "), "\n"
        end
      end

      if param['long'] || param['likelihood']
        out = param['tail'] ? info + @final + [@contrib[0]] : @final + [@contrib[0]] + info
      else
        out = param['tail'] ? info + [@final[0], @contrib[0]] : [@final[0], @contrib[0]] + info
      end
      print out.join(separator), "\n"
      print "\n" if param['likelihood']
      self
    end

  end

end
