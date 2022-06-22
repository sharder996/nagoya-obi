#!/usr/bin/python3

############################################################################
#
# obi-2.x:	bigramを用いた日本語テキストの難易度推定
#
#
#  Copyright (c) Satoshi Sato, 2009.
#  License: Creative Commons 3.0, Attribution-Noncommercial-Share Alike.
#
############################################################################

import argparse
import nagoyaobi
import re
import sys
from argparse import RawTextHelpFormatter

KCODE = 'utf8'

Version = 'obi2.305 (2009-08-12)'
ModelDir = '.'
DefaultModelName = 'T13'


class SmoothingAction(argparse.Action):
	def __init__(self, option_strings, dest, nargs=None, **kwargs):
		if nargs is not None:
			raise ValueError('nargs is not allowed')
		super().__init__(option_strings, dest, **kwargs)

	def __call__(self, parser, namespace, values, option_string=None):
		values = [int(v) for v in values.split('\\,')]
		setattr(namespace, self.dest, values)


def init_argparse() -> argparse.ArgumentParser:
	parser = argparse.ArgumentParser(
		# usage='%(prog)s [switches] [files]',
		description='Each level of the T13 (T13U) scale model corresponds to a Japanese school grade level; i.e.,\n'
					'\t{0:>7}: elementary school (6 years)\n'
					'\t{1:>7}: junior high school (3 years)\n'
					'\t{2:>7}: high school (3 years)\n'
					'\t{3:>7}: beyond high school\n'
					'\n'
					'By default, this program produces two integers:\n'
					'\tfirst: readability level\n'
					'\tsecond: the number of operative characters in the text'
			.format('1 - 6', '7 - 9', '10 - 12', '13'),
		formatter_class=RawTextHelpFormatter
	)
	parser.add_argument('-m', '--model_name', choices=['T13', 'T13U'], #default='T13',
						help='scale model name [DEFAULT: T13]')
	parser.add_argument('-M', '--model_file', help='scale model file')

	parser.add_argument('-o', '--operative_char', default=f'{ModelDir}/jchar.utf8')
	parser.add_argument('-N', '--ngram', type=int, choices=[1, 2], default=2)

	parser.add_argument('-k', '--kanji', choices=['E', 'S', 'J', 'W'], help='kanji code of the text files')

	parser.add_argument('-D', '--corpus_dir', default=None)
	parser.add_argument('-d', '--corpus_def')
	parser.add_argument('-t', '--test_def')

	parser.add_argument('-f', '--required_frequency', type=int, default=1)
	parser.add_argument('-s', '--smoothing', action=SmoothingAction)

	parser.add_argument('-O', '--model_output')

	parser.add_argument('-l', '--long_output', action='store_true', help='display long output')
	parser.add_argument('-T', '--tail_output', action='store_true')
	parser.add_argument('-L', '--likelihood', action='store_true', help='display likelihood values of levels')

	parser.add_argument('-x', '--exec_mode', choices=['size', 'bigram', 'cross_validation'])
	parser.add_argument('-p', '--partition', type=int, default=2)

	parser.add_argument('-i', '--input', nargs='+')

	parser.add_argument('-v', '--version', action='version', version=f'{parser.prog} {Version}\n'
		f'This program is distributed under the following license:\n'
		f'\tCreative Commons 3.0, Attribution Noncommercial Share Alike.', help='display version')

	return parser


def main() -> None:
	parser = init_argparse()
	args = vars(parser.parse_args())

	show_param = dict()
	if args['long_output']:
		show_param['long'] = True
	if args['tail_output']:
		show_param['tail'] = True
		show_param['separator'] = '\t'
	if args['likelihood']:
		show_param['likelihood'] = True

	if args['exec_mode'] == 'size':
		if args['kanji']:
			nagoyaobi.default_kanji_code(args['kanji'])
		if args['ngram']:
			if args['ngram'] == 1:
				nagoyaobi.use_unigram()
				nagoyaobi.corpus_size(args['corpus_def'], args['corpus_dir'],
									  nagoyaobi.load_operative_character_file(args['operative_char']))
			else:
				nagoyaobi.corpus_size(args['corpus_def'], args['corpus_dir'], None)
	else:
		if args['ngram'] == 1:
			nagoyaobi.use_unigram()
		op_char = nagoyaobi.load_operative_character_file(args['operative_char'])

		if args['exec_mode'] == 'bigram':  # Output bigram (for debug)
			if len(args['input']) == 0:
				for b in nagoyaobi.operative_ngram_from_io(sys.stdin, args['kanji'], op_char):
					print(b, end='\n')
			else:
				for file in args['input']:
					with open(file, 'r', encoding='utf-8') as f:
						for b in nagoyaobi.operative_ngram_from_io(f, args['kanji'], op_char):
							print(b, end='\n')
		elif args['exec_mode'] == 'cross_validation':  # Evaluation experiment mode
			if args['partition'] == 1:  # Evaluation experiment mode (leave-one-out)
				# Step 1: Load corpus criteria
				corpus, definition = nagoyaobi.load_corpus_from_def(args['corpus_def'], args['corpus_dir'], op_char,
																	args['kanji'])
				# Step 2: Load test set
				if args['test_def']:
					definition = nagoyaobi.load_corpus_definition(args['test_def'])
				# Step 3: For each sample
				for info in definition:
					file = info[0]
					grade = int(info[2])
					# Step 2a: Load sample
					text = nagoyaobi.load_text('/'.join([args['corpus_dir'], file]), info[1] or args['kanji'], op_char)
					# Step 2b: Create model
					model = nagoyaobi.make_model(nagoyaobi.make_corpus_for_leave_one_out(corpus, text, grade),
												 args['required_frequency'])
					# Step 2c: Evaluate sample difficulty
					model.readability0(text, args['smoothing']).show(info, show_param)
			else:  # Evaluation experiment mode (N-fold cross validation)
				# Step 1: Load corpus definition
				definition = nagoyaobi.load_corpus_definition(args['corpus_def'])
				# Step 2: Divide the sample
				partition = list()
				i = 0
				for info in definition:
					p = i % args['partition']
					for _ in range(p - len(partition) + 1):
						partition.append([])
					partition[p].append(info)
					i += 1
				# Step 3: Run for each partition
				for p in range(args['partition']):
					# Create language model
					corpus = nagoyaobi.load_partition_corpus(args['corpus_dir'], partition, p, op_char, args['kanji'])
					model = nagoyaobi.make_model(corpus, args['required_frequency'])
					# Evaluate difficulty
					for x in partition[p]:
						model.readability('/'.join([args['corpus_dir'], x[0]]), x[1] or args['kanji'], op_char,
										  args['smoothing'])\
							.show(x, show_param)
		else:  # Normal execution mode
			# Step 1: Prepare model
			# Load the model if given
			if args['model_file']:
				model = nagoyaobi.load_model_file(args['model_file'], args['required_frequency'])
			elif args['model_name']:
				model = nagoyaobi.load_model(args['model_name'], ModelDir, args['required_frequency'])
			elif args['corpus_def']:
				# Load corpus criteria
				corpus, definition = nagoyaobi.load_corpus_from_def(args['corpus_def'], args['corpus_dir'], op_char,
																	args['kanji'])
				# Create language model
				model = nagoyaobi.make_model(corpus, args['required_frequency'])
				# Save language model
				if args['model_output']:
					model.save_model(args['model_output'])
			else:
				model = nagoyaobi.load_model(DefaultModelName, ModelDir, args['required_frequency'])

			# Step 2: Evaluate difficulty
			if args['test_def']:
				# The text file to be evaluated is specified by --test_def
				definition = nagoyaobi.load_corpus_definition(args['test_def'])
				for info in definition:
					model.readability('/'.join([args['corpus_dir'], info[0]]), info[1] or args['kanji'], op_char,
									  args['smoothing']).show(info, show_param)
			elif len(args['input']) == 0:
				if args['model_output']:
					# Model creation only; Difficulty evaluation not performed
					pass
				elif args['corpus_dir']:
					# Read the filename to be evaluated from stdin
					for line in sys.stdin:
						line = re.split(r'\s+', line.strip('\r\n'))
						model.readability('/'.join([args['corpus_dir'], line[0]]), line[1] or args['kanji'], op_char,
										  args['smoothing']).show(line, show_param)
				else:
					# Read the text to be evaluated from stdin
					model.readability(sys.stdin, args['kanji'], op_char).show([], show_param)
			else:
				# The filename to be evaluated is specified in the arguments
				for file in args['input']:
					model.readability(file, args['kanji'], op_char, args['smoothing'])\
						.show([file], show_param)


if __name__ == '__main__':
	main()
