# nagoya-obi

Python port of nagoya obi reading difficulty statistic by Satoshi Sato. The research behind the statistic can be found in the following papers:

- [日本語テキストの難易度判定ツール『帯』](https://www.japio.or.jp/00yearbook/files/2008book/08_1_03.pdf)
- [Automatic Assessment of Japanese Text Readability Based on a Textbook Corpus](http://www.lrec-conf.org/proceedings/lrec2008/pdf/165_paper.pdf) 

A web version of the tool can also be found [here](http://kotoba.nuee.nagoya-u.ac.jp/sc/obi3/) on the author's website.

#### Python3 port

The python port of the original program is largely untested outside standard reading difficulty text evaluation so use at your own risk. Evaluating text is done with the following command:

```(bash)
python3 ./obi2.py -i ./text.txt
```

An executable version of the program is also available under releases which was datamined from a text analysis tool found [here](https://sourceforge.net/projects/japanesetextana/).  
