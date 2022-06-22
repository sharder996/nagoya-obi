import functools
import math
import matrix
from itertools import starmap
from operator import mul


def regression(k: int, y: list, x: list) -> list:
	if not x:
		x = [float(i) for i in range(len(y))]
	return regression_values(regression_parameters(k, y, x), x)


def regression_parameters(k: int, y: list, x: list) -> list:
	n = len(y)

	a_inv = matrix.inverse([
		[
			functools.reduce(lambda sum, i: sum + math.pow(x[i], j+l), range(n), 0.0) for l in range(k+1)
		] for j in range(k+1)
	])
	b = [[functools.reduce(lambda sum, i: sum + y[i] * math.pow(x[i], j), range(n), 0.0)] for j in range(k+1)]

	# c = a_inv * b
	c = [[sum(starmap(mul, zip(row, col))) for col in zip(*b)] for row in a_inv]

	return [c[i][0] for i in range(k+1)]


def regression_values(p: list, xs: list) -> list:
	return [regression_value(p, x) for x in xs]


def regression_value(p: list, x: float) -> float:
	return functools.reduce(lambda retval, i: retval + p[i] * math.pow(x, i), range(len(p)), 0)
