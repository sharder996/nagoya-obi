###########################################################################################
#
# 名古屋帯：bigramを用いた日本語テキストの難易度推定
# NagoyaObi: readability accessment of Japanese texts based on character-bigram models
#
# Copyright (c) Satoshi Sato, 2009
#
# License: Creative Commons 3.0, Attribution-Noncommercial-Share Alike.
#
###########################################################################################

import copy
import io
import math
import nkf
import re
import regression
from typing import Generator
from typing import TextIO
from typing import Tuple


__N = 2
__KanjiCode = None


class Result:
	MethodList = ['ns', 's5', 's4', 's3', 's2']
	VotingList = ['ns', 's4', 's2']

	def __init__(self, text: dict, contrib: list, model_spec: str = None, smoothing: list = None):
		self.text = text
		self.contrib = contrib
		self.voting_list = self.VotingList
		self.estimate = self.make_estimation(self.contrib)
		if smoothing:
			self.set_voting_list(['ns' if v == 0 else f's{v}' for v in smoothing])
		if model_spec == 'T7':
			self.final = [self.t7_scale_transform(v) for v in self.final_estimation(self.estimate)]
		else:
			self.final = self.final_estimation(self.estimate)

	def set_voting_list(self, list: list):
		self.voting_list = list

	def make_estimation(self, contrib: list) -> dict:
		estimat = dict()

		operative_len = contrib[0]
		if operative_len > 0:
			estimat['ns'] = [100 * contrib[i] / operative_len for i in range(1, len(contrib))]
			for i in range(2, 6):
				estimat[f's{i}'] = regression.regression(i, estimat['ns'], None)
		return estimat

	def final_estimation(self, estimat: dict) -> list:
		if len(estimat) > 0:
			list = [estimat[x].index(max(estimat[x]))+1 for x in self.MethodList]
			temp = sorted([estimat[x].index(max(estimat[x]))+1 for x in self.voting_list])
			return [temp[int(len(temp)/2)]] + list if int(len(temp)) % 2 != 0 \
				else [(temp[int(len(temp)/2-1)] + temp[int(len(temp)/2)]) / 2] + list
		else:
			return [0] * len(self.MethodList)

	def grade(self, t7=None) -> int:
		if t7:
			return self.t7_scale_transform(self.final[0])
		else:
			return self.final[0]

	def t7_scale_transform(self, val: int) -> int:
		if val == 0:
			return 0
		elif val <= 6:
			return 1
		elif val == 13:
			return 7
		elif 11 <= val <= 12:
			return 6
		else:
			return 5

	def show(self, info: list = [], param: dict = {}):
		separator = ' '
		if 'separator' in param and param['separator']:
			separator = param['separator']

		if 'contrib' in param and param['contrib']:
			for key in self.text:
				c = self.text[key]
				c[0] = f'{c[0]:3d}'
				for i in range(1, len(c)):
					c[i] = f'{c[i]:6.2f}'
				c.insert(0, key)
				print(*c, end='\n')
			print('\n')

		if 'likelihood' in param and param['likelihood']:
			for v in self.MethodList:
				print(*[v, f'{self.estimate[v].index(max(self.estimate[v])+1):2d}',
						' '.join([f'{x:6.2f}' for x in self.estimate[v]])], end='\n')

		if ('long' in param and param['long']) or ('likelihood' in param and param['likelihood']):
			out = info + self.final + [self.contrib[0]] if 'tail' in param and param['tail'] else self.final + [self.contrib[0]] + info
		else:
			out = info + [self.final[0], self.contrib[0]] if 'tail' in param and param['tail'] else [self.final[0], self.contrib[0]] + info
		print(*out, sep=separator, end='\n')
		if 'likelihood' in param and param['likelihood']:
			print('\n')
		return self


class Model:
	def __init__(self, model: dict, spec: str = None):
		self.model_spec = spec
		self.model = model

	def save_model(self, model_output: str) -> None:
		"""
		Save model
		"""
		with open(model_output, 'w') as f:
			for key in self.model:
				out = [key] + [self.model[key][0]] + [f'{self.model[key][i]:.5f}' for i in range(1, len(self.model[key]))]
				f.write('\t'.join(out) + '\n')

	def readability(self, io_spec, kanji_code_spec: str, op_char: dict, smoothing: list = None) -> Result:
		return self.readability0(load_text(io_spec, kanji_code_spec, op_char), smoothing)

	def readability0(self, text: dict, smoothing: list = None) -> Result:
		return Result(text, self.calculate_likelihoods(text), self.model_spec, smoothing)

	def calculate_likelihoods(self, text: dict) -> list:
		total = [0]
		for key in list(text.keys()):
			if key in self.model:
				total[0] += text[key][0]
				for i in range(1, len(self.model[key])):
					if len(total) <= i:
						total.append(0.0)
					if len(text[key]) <= i:
						text[key].append(0.0)
					text[key][i] = text[key][0] * self.model[key][i]
					total[i] += text[key][i]
			else:
				del text[key]  # Not a valid bigram!
		return total


def version() -> str:
	return 'NagoyaObi 2.305 (2009-08-12) Copyright 2009, Satoshi Sato'


def default_kanji_code(val: str) -> None:
	global __KanjiCode
	__KanjiCode = val


def use_unigram() -> None:
	global __N
	__N = 1


def use_bigram() -> None:
	global __N
	__N = 2


def load_operative_character_file(filename: str) -> dict:
	"""
	Load valid character definition file/check valid bigram
	"""
	operative = dict()
	with open(filename, 'r', encoding='utf-8') as f:
		for line in f:
			operative[line.strip('\r\n').split('\t')[0]] = True
	return operative


def is_operative(bigram: str, operative: dict) -> bool:
	for c in list(bigram):
		if c not in operative:
			return False
	return True


def get_kanji_code(spec: str, kanji_code: str = None) -> str:
	"""
	Kanji code (E, J, S, W)
	"""
	if spec and spec == 'W':
		return None  # No change
	elif spec and re.search(r'^[EJS]$', spec):  # W16 does not work properly!
		return spec  # Change kanji code
	elif spec:
		raise ValueError(f'{spec} is not a valid kanji specification!')
	elif kanji_code:
		return kanji_code
	elif __KanjiCode:
		return __KanjiCode  # Default
	else:
		return None


def bigram_from_io(io: TextIO, kanji_code: str = None) -> Generator[str, None, None]:
	"""
	Get bigram
	"""
	c = list()
	for line in io:
		if kanji_code:
			line = nkf.nkf(f'{kanji_code}w', line)
		line = line.strip('\r\n')

		if re.search(r'^\s*$', line) or re.search(r'^<', line):  # If line is whitespace or a tag, do not continue the line
			c = list()

		# Format text
		tail_tag = re.search(r'>$', line)
		line = re.sub(r'<[^<]*>', '', line)
		line = re.sub(r'\s', '', line)

		# Create bigram
		c += list(line)
		for _ in range(len(c)-1):
			b = ''.join(c[0:2])
			yield b
			c.pop(0)

		if tail_tag:  # If the end of a line is a tag, terminate the line
			c = list()


def unigram_from_io(io: TextIO, kanji_code: str = None) -> Generator[str, None, None]:
	"""
	Get unigram
	"""
	for line in io:
		if kanji_code:
			line = nkf.nkf(f'{kanji_code}w', line)
		line = line.strip('\r\n')

		# Format text
		line = re.sub(r'<[^<]*>', '', line)  # Delete tags
		line = re.sub(r'\s', '', line)  # Delete whitespace

		# Create unigram
		for c in list(line):
			yield c


def operative_ngram_from_io(io: TextIO, kanji_code: str, op_char: dict, n: int = __N) -> Generator[str, None, None]:
	"""
	n-gram
	"""
	if n == 1:
		if op_char:
			for c in unigram_from_io(io, kanji_code):
				if c in op_char:
					yield c
		else:
			for c in unigram_from_io(io, kanji_code):
				yield c
	else:
		for b in bigram_from_io(io, kanji_code):
			if is_operative(b, op_char):
				yield b


def load_corpus_definition(filename: str) -> list:
	"""
	Load corpus definition file
	"""
	definition = list()
	with open(filename, 'r') as f:
		for line in f:
			definition.append(line.strip('\r\n').split('\t'))  # file_spec \t kanji \t grade \t info ...
	return definition


def load_corpus(corpus_dir: str, definition: list, operative: dict, kanji_code: str = None) -> dict:
	"""
	Load/create corpus
	"""
	corpus = dict()
	grades = 0

	for d in definition:
		grade = int(d[2])
		with open('/'.join([corpus_dir, d[0]])) as f:
			for b in operative_ngram_from_io(f, get_kanji_code(d[1], kanji_code), operative):
				if b not in corpus:
					corpus[b] = list()
				if grade < len(corpus[b]):
					corpus[b][grade] += 1
				else:
					for _ in range(grade - len(corpus[b]) + 1):
						corpus[b].append(0)
					corpus[b][grade] = 1

		grades = max(grades, grade)
	return load_corpus_sub(corpus, grades)


def load_corpus_sub(corpus, grades) -> dict:
	for key in corpus:
		corpus[key] += [0] * (grades+1 - len(corpus[key]))  # Satisfy missing element at end
		corpus[key][0] = sum(corpus[key])  # Put sum at beginning
	return corpus


def load_partition_corpus(corpus_dir: str, partition: list, p: int, operative: dict, kanji_code: str = None) -> dict:
	corpus = dict()
	grades = 0

	# Load file
	for i in range(len(partition)):
		if i == p:
			continue
		for d in partition[i]:
			grade = int(d[2])
			with open('/'.join([corpus_dir, d[0]]), 'r', encoding='utf-8') as f:
				for b in operative_ngram_from_io(f, get_kanji_code(d[1], kanji_code), operative):
					if b not in corpus:
						corpus[b] = []
					if grade < len(corpus[b]):
						corpus[b][grade] += 1
					else:
						for _ in range(grade - len(corpus[b]) + 1):
							corpus[b].append(0)
						corpus[b][grade] = 1
			grades = max(grades, grade)
	return load_corpus_sub(corpus, grades)


def make_corpus_for_leave_one_out(corpus: dict, text: dict, grade: int) -> dict:
	"""
	Create a corpus for leave_one_out
	"""
	cp = copy.deepcopy(corpus)  # Copy
	for key in text:
		if key in cp:
			cp[key][grade] -= text[key][0]  # Subtract the frequency of the corresponding grade
			cp[key][0] -= text[key][0]  # Subtract the total

	return cp


def load_corpus_from_def(corpus_def: str, corpus_dir: str, op_char: dict, kanji_code: str = None) -> Tuple[dict, list]:
	"""
	Load corpus definition file
	"""
	# Step 1: Load corpus definition file
	definition = load_corpus_definition(corpus_def)
	# Step 2: Load corpus
	corpus = load_corpus(corpus_dir, definition, op_char, kanji_code)

	return corpus, definition


def corpus_size(corpus_def: str, corpus_dir: str, op_char: dict = None) -> None:
	"""
	Corpus size
	"""
	# Step 1: Load corpus definition file
	definition = load_corpus_definition(corpus_def)
	# Step 2: Load corpus
	corpus = load_corpus(corpus_dir, definition, op_char)

	all = None
	for key in corpus:
		all = add_list(all, corpus[key])

	print(' '.join(all), end='\n')


def load_text(io_spec, kanji_code_spec: str, op_char: dict) -> dict:
	"""
	Load text
	"""
	text = dict()
	kanji_code = get_kanji_code(kanji_code_spec)

	if isinstance(io_spec, io.TextIOBase) or isinstance(io_spec, list):
		for b in operative_ngram_from_io(io_spec, kanji_code, op_char):
			if b not in text:
				text[b] = [0]
			text[b][0] += 1
	elif isinstance(io_spec, str):
		with open(io_spec, 'r', encoding='utf-8') as f:
			for b in operative_ngram_from_io(f, kanji_code, op_char):
				if b not in text:
					text[b] = [0]
				text[b][0] += 1
	return text


def make_model(corpus: dict, required_frequency: int) -> Model:
	"""
	Create model
	"""
	# Delete infrequent bigrams
	if required_frequency > 0:
		for key, value in corpus.items():
			if value[0] < required_frequency:
				del corpus[key]

	total = make_total(corpus)

	model = dict()
	for key in corpus:
		f = key[0]  # Get first character
		model[key] = make_model_sub(corpus[key], total[f])

	return Model(model)


def make_total(corpus: dict) -> dict:
	if __N == 1:
		return make_total_unigram(corpus)
	else:
		return make_total_bigram(corpus)


def make_total_bigram(corpus: dict) -> dict:
	total = dict()
	for key in corpus:
		f = key[0]  # Get first character
		total[f] = add_list(total[f], corpus[key])
	return total


def make_total_unigram(corpus: dict) -> dict:
	all = None
	for key in corpus:
		all = add_list(all, corpus[key])

	total = dict()
	for key in corpus:
		total[key] = all
	return total


def add_list(sum: list, add: list) -> list:
	if sum:
		for i in range(len(sum)):
			sum[i] += add[i]
		return sum
	else:
		return add.copy()


def make_model_sub(f: list, total: list) -> list:
	"""
	Calculate normalized likelihood for bigram
	"""
	# Calculate probability
	p = [0.0 if f[i] == 0 else float(f[i]) / total[i] for i in range(1, len(f))]
	p.insert(0, f[0])

	# Linear interpolation (eliminates 0 probabilities)
	p = interpolate(p)

	# Convert to log probability
	w = [math.log(p[i], 10) for i in range(1, len(p))]

	# Take difference from average
	average = sum(w) / len(w)
	for i in range(len(w)):
		w[i] = w[i] - average

	w.insert(0, f[0])  # Insert first element from f
	return w


def interpolate(f: list) -> list:
	"""
	Linear interpolation
	"""
	v = [float(x) for x in f]  # Convert to float
	v.pop(0)  # Discard the first element (total)
	zeros = [x == 0.0 for x in v]
	while True in zeros:
		v = interpolate_sub(v, zeros)
		zeros = [x == 0.0 for x in v]
	v.insert(0, f[0])  # Insert first element from f (original appearance frequency)
	return v


def interpolate_sub(v: list, zeros: list) -> list:
	new = list()
	for i in range(len(v)):
		if zeros[i]:
			if i == 0:
				new[i] = v[i+1] / 2
			elif i == len(v)-1:
				new[i] = v[i-1] / 2
			else:
				new[i] = (v[i-1] + v[i+1]) / 2
		else:
			new[i] = v[i]
	return new


def load_model(model_spec: str, model_dir: str, required_frequency: int) -> Model:
	return load_model_file(make_model_filename(model_spec, model_dir), required_frequency, model_spec)


def load_model_file(filename: str, required_frequency: int, model_spec: str = None) -> Model:
	model = dict()
	with open(filename, 'r', encoding='utf-8') as f:
		for line in f:
			x = line.strip('\r\n').split('\t')
			if int(x[1]) >= required_frequency:
				key = x.pop(0)
				model[key] = [int(x.pop(0))] + [float(v) for v in x]
	return Model(model, model_spec)


def make_model_filename(name: str, dir: str) -> str:
	if name == 'T7':
		return f'{dir}/Obi2-T13.model'
	else:
		return f'{dir}/Obi2-{name}.model'
