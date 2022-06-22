#!/usr/local/bin/ruby -w

############################################################################
###
### obi-2.x:	bigramを用いた日本語テキストの難易度推定
### 
###
###  Copyright (c) Satoshi Sato, 2009.
###  License: Creative Commons 3.0, Attribution-Noncommercial-Share Alike.
###
############################################################################

require '..\lib\nagoyaobi'
require '..\lib\getoptlong'

$KCODE = 'utf8'
STDOUT.sync = true

Version = 'obi2.305 (2009-08-12)'

###
### 引数(arguments)
### 
opts = GetoptLong.new(
           [ "--model_name", "-m", GetoptLong::REQUIRED_ARGUMENT ], # モデル名
           [ "--model_file", "-M", GetoptLong::REQUIRED_ARGUMENT ], # モデルファイル名

           [ "--operative_char", "-o", GetoptLong::REQUIRED_ARGUMENT ], # 有効文字
           [ "--ngram", "-N", GetoptLong::REQUIRED_ARGUMENT ], # ngram (n=2 or 1)

           [ "--kanji", "-k", GetoptLong::REQUIRED_ARGUMENT ], # defaultの漢字コード	

           [ "--corpus_dir", "-D", GetoptLong::REQUIRED_ARGUMENT ], # コーパスディレクトリ
           [ "--corpus_def", "-d", GetoptLong::REQUIRED_ARGUMENT ], # 規準コーパス定義
           [ "--test_def",   "-t", GetoptLong::REQUIRED_ARGUMENT ], # テストサンプル定義
                      # （評価においては、規準コーパス定義のサブセットであることが必要！）

           [ "--required_frequency", "-f", GetoptLong::REQUIRED_ARGUMENT ], # 最低頻度
           [ "--smoothing", "-s", GetoptLong::REQUIRED_ARGUMENT ], # スムージング

           [ "--model_output", "-O", GetoptLong::REQUIRED_ARGUMENT ], # モデル出力ファイル名

           [ "--long_output", "-l", GetoptLong::NO_ARGUMENT ], # 長い出力
           [ "--tail_output", "-T", GetoptLong::NO_ARGUMENT ], # 難易度表示を末尾に
           [ "--likelihood",  "-L", GetoptLong::NO_ARGUMENT ], # 尤度の表示

           [ "--exec_mode",  "-x", GetoptLong::REQUIRED_ARGUMENT ], # 実行モード指定
           [ "--partition",  "-P", GetoptLong::REQUIRED_ARGUMENT ], # 実行モード指定

           [ "--help",       "-h", GetoptLong::NO_ARGUMENT ], # helpの表示
           [ "--Help",       "-H", GetoptLong::NO_ARGUMENT ], # helpの表示
           [ "--version",    "-v", GetoptLong::NO_ARGUMENT ]  # versionの表示
                      )

$MyOpts = Hash.new
begin
  opts.each do |opt, arg|
    $MyOpts[opt] = arg
  end
rescue
  exit(1)
end

###
### 定数(constants)
### 
ModelDir   = '.'
DefaultModelName = 'T13'

###
### パラメータ
###
Mode        = $MyOpts['--exec_mode'] || nil

OpCharDef   = $MyOpts['--operative_char'] || "#{ModelDir}/jchar.utf8"
CorpusDir   = $MyOpts['--corpus_dir']     || nil
CorpusDef   = $MyOpts['--corpus_def']
TestDef     = $MyOpts['--test_def']
ModelOutput = $MyOpts['--model_output']
RequiredFrequency = $MyOpts['--required_frequency'] ? $MyOpts['--required_frequency'].to_i : 1
Smoothing = $MyOpts['--smoothing'] ? $MyOpts['--smoothing'].split(/\,/).collect{|v| v.to_i} : nil

KanjiCode = $MyOpts['--kanji'] || nil
Ngram     = ( $MyOpts['--ngram'] ? $MyOpts['--ngram'].to_i :
              ($MyOpts['--model_name'] and $MyOpts['--model_name'] =~ /U$/) ? 1 : 2 )

Partition = $MyOpts['--partition'] ? $MyOpts['--partition'].to_i : 2

show_param = Hash.new
show_param['long'] = true if $MyOpts['--long_output']
if $MyOpts['--tail_output']
  show_param['tail'] = true; show_param['separator'] = "\t"
end
show_param['likelihood'] = true if $MyOpts['--likelihood']

###
### Version
### 
def version ()

  print <<END_OF_HELP
#{[Version, NagoyaObi.version].join(" + ")}
This program is distributed under the following license:
  Creative Commons 3.0, Attribution-Noncommercial-Share Alike.
END_OF_HELP
end

def usage(long=nil)
  print <<END_OF_USAGE
This program measures readability of Japanese texts.

Usage: obi [switches] [files]
  -m T13|T13U    scale model name (--model_name) [DEFAULT: T13]
  -M model_file  scale model file (--model_file)
  -k kanji_code  kanji code of the text files; specify one of E, S, J, W

  -l             display long output
  -L             display likelihood values of levels 
        
  -v             display version (--version)
  -h             display this message (--help)

Each level of the T13 (T13U) scale model corresponds a Japanese school grade level; i.e., 
   1- 6: elementary school (6 years)
   7- 9: junior high school (3 years)
  10-12: high school (3 years)
     13: beyond high school

In default, this program produces two integers:
  first: readability level
  second: the number of operative characters in the text
END_OF_USAGE

  return unless long

  print <<END_OF_USAGE

[Model genration mode]
Usage: obi2 -O filename [switches] [files]
  -d def_file    corpus definition
  -D corpus_dir  the root directory of the corpus
  -o op_char     the definition file of the operative characters
  -k kanji_code  kanji code of text; specify one of E, S, J, W
  -N 2|1         n of n-gram
  -O filename    the output filename

[Evaluation mode]
Usage: obi2 -x cross_validation [switches]
  -P n           n-fold cross validation; n = 1 means leave_one_out cross valication
  -d def_file    corpus definition
  -D corpus_dir  the root directory of the corpus
  -o op_char     the definition file of the operative characters
  -k kanji_code  kanji code of text; specify one of E, S, J, W
  -N 2|1         n of n-gram

END_OF_USAGE
end

###
### 実行
### 
if $MyOpts['--version']
  version()
elsif $MyOpts['--help']
  usage()
elsif $MyOpts['--Help']
  usage(true)

elsif Mode == 'size'                    # サイズの調査

  # $MyOpts['--ngram']を指定した場合は、有効ngram数；指定しなかった場合は文字数
  NagoyaObi.default_kanji_code(KanjiCode) if KanjiCode
  if $MyOpts['--ngram']
    NagoyaObi.use_unigram if Ngram == 1
    NagoyaObi.corpus_size(CorpusDef, CorpusDir, NagoyaObi.load_operative_character_file(OpCharDef))
  else
    NagoyaObi.corpus_size(CorpusDef, CorpusDir, nil)
  end

else
  NagoyaObi.use_unigram if Ngram == 1
  op_char = NagoyaObi.load_operative_character_file(OpCharDef)

  if Mode == 'bigram'                  # bigramを出力（debug用）	

    if ARGV.length == 0
      NagoyaObi.operative_ngram_from_io(STDIN, KanjiCode, op_char) {|b| print b, "\n"}
    else
      ARGV.each do |file|
        File.open(file) do |io|    
          NagoyaObi.operative_ngram_from_io(io, KanjiCode, op_char) {|b| print b, "\n"}
        end
      end
    end

  elsif Mode == 'cross_validation'     # 評価実験モード

    if Partition == 1                  # 評価実験モード (leave-one-out)

      # Step 1: 規準コーパスのロード
      corpus, definition = *NagoyaObi.load_corpus_from_def(CorpusDef, CorpusDir, op_char, KanjiCode)
      # Step 2: テストセットのロード
      definition = NagoyaObi.load_corpus_definition(TestDef) if TestDef
      # Step 3: それぞれのサンプルに対して
      definition.each do |info|
        file = info[0]; grade = info[2].to_i
        # Step 2a: サンプルのロード
        text = NagoyaObi.load_text([CorpusDir,file].join("/"), info[1]||KanjiCode, op_char)
        # Step 2b: モデルの作成
        model = NagoyaObi.make_model(NagoyaObi.make_corpus_for_leave_one_out(corpus, text, grade), 
                                     RequiredFrequency)
        # Step 2c: サンプルの難易度評価
        model.readability0(text,Smoothing).show(info, show_param)
      end

    else                                # 評価実験モード (N-fold cross validation)

      # Step 1: コーパス定義のロード
      definition = NagoyaObi.load_corpus_definition(CorpusDef)
      # Step 2: サンプルをN分割する
      partition = []; i = 0
      definition.each do |info|
        p = i % Partition
        partition[p] ||= []; partition[p] << info
        i += 1
      end
      # Step 3: それぞれのパーティションに対して実行
      (0 ... Partition).each do |p|
        # 言語モデルの作成
        corpus = NagoyaObi.load_partition_corpus(CorpusDir, partition, p, op_char, KanjiCode)
        model = NagoyaObi.make_model(corpus, RequiredFrequency)
        # 難易度の評価
        partition[p].each do |x|
          model.readability([CorpusDir,x[0]].join("/"), 
                            x[1]||KanjiCode, op_char ,Smoothing).show(x, show_param)
        end
      end

    end

  else  # 通常実行モード

    # Step 1: モデルの準備
    # モデルが与えられている場合は、モデルをロードする
    if $MyOpts['--model_file']
      model = NagoyaObi.load_model_file($MyOpts['--model_file'], RequiredFrequency)
    elsif $MyOpts['--model_name']
      model = NagoyaObi.load_model($MyOpts['--model_name'], ModelDir, RequiredFrequency)
    elsif CorpusDef
      # 規準コーパスのロード
      corpus, definition = *NagoyaObi.load_corpus_from_def(CorpusDef, CorpusDir, op_char, KanjiCode)
      # 言語モデルの作成
      model = NagoyaObi.make_model(corpus, RequiredFrequency)
      # 言語モデルのセーブ
      model.save_model(ModelOutput) if ModelOutput
    else
      model = NagoyaObi.load_model(DefaultModelName, ModelDir, RequiredFrequency)
    end

    # Step 2: 難易度の評価
    if TestDef
      # 評価すべきテキストファイル名が、--test_def で指定されている
      definition = NagoyaObi.load_corpus_definition(TestDef)
      definition.each do |info|
        model.readability([CorpusDir,info[0]].join("/"), 
                          info[1]||KanjiCode, op_char, Smoothing).show(info, show_param)
      end
    elsif ARGV.length == 0
      if $MyOpts['--model_output']
        # モデルの作成のみ；難易度評価は実行せず
      elsif $MyOpts['--corpus_dir']
        # 標準入力から、評価すべきテキストファイル名を読み込む
        ARGF.each do |line|
          line.chomp!
          x = line.split(/\s+/)
          model.readability([CorpusDir,x[0]].join("/"), 
                            x[1]||KanjiCode, op_char, Smoothing).show(x, show_param)
        end
      else
        # 標準入力から、評価すべきテキストを読み込む
        model.readability(STDIN, KanjiCode, op_char).show([], show_param)
      end
    else
      # 引数に、評価すべきファイル名が与えられている
      ARGV.each do |file|
        model.readability(file, KanjiCode, op_char, Smoothing).show([file], show_param)
      end
    end
  end
end
