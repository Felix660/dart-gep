// -*- compile-command: "cd ../.. && ./df.sh"; -*-

import 'dart:math';
import 'dart:mirrors';

import 'package:meta/meta.dart';

import 'bool_nodes/nand_nodes.dart';
import 'double_nodes/double_nodes.dart';
import 'int_nodes/int_nodes.dart';
import 'vector_bool_nodes/vector_bool_nodes.dart';
import 'vector_double_nodes/vector_double_nodes.dart';
import 'vector_int_nodes/vector_int_nodes.dart';

import 'functions.dart';
import 'vector.dart';
import 'weighted_symbol.dart';

/// Gene represents a single GEP gene.
/// It contains the symbols useds in the gene's expression.
class Gene<T> {
  Gene(this.allFuncs) {}

  /// Creates a new gene based on the Karva string representation.
  Gene.fromKarva(String karva, this.allFuncs)
      : symbols = [],
        constants = [],
        headSize = 0,
        numTerminals = 0,
        numConstants = 0,
        symbolMap = {} {
    var numInputs = 0;
    final parts = karva.split('.');
    parts.forEach((part) {
      var sym = Symbol(part);
      symbols.add(sym);
      symbolMap[sym] ??= 0;
      if (part.startsWith('d')) {
        final index = num.parse(part.substring(1));
        if (index >= numInputs) numInputs = index + 1;
      } else if (part.startsWith('c')) {
        final index = num.parse(part.substring(1));
        if (index >= numConstants) numConstants = index + 1;
      }
    });
    constants = List<T>.filled(numConstants, zeroValue);
    numTerminals = numInputs + numConstants;

    var ao = argOrder();
    model = buildModel(0, ao);
  }

  genRandomConstants() {
    // Override this.
    constants = List.generate<T>(numConstants, (index) => zeroValue);
  }

  // RandomNew generates a new, random gene for further manipulation by the GEP
  // algorithm. The headSize, numTerminals, and numConstants determine the respective
  // properties of the gene, and functions provide the available functions and
  // their respective weights to be used in the creation of the gene.
  Gene.random(this.headSize, this.numTerminals, this.numConstants,
      List<WeightedSymbol> functions, this.allFuncs) {
    symbolMap = {};
    var totalWeight = numTerminals + numConstants;
    var maxArity = 0;
    for (var f in functions) {
      totalWeight += f.weight;
      final int n = allFuncs[f.symbol].terminals;
      if (n > maxArity) maxArity = n;
    }
    int tailSize = headSize * (maxArity - 1) + 1;
    var terminalNames =
        List.generate<Symbol>(numTerminals, (index) => Symbol('d$index'));
    var constantNames =
        List.generate<Symbol>(numConstants, (index) => Symbol('c$index'));
    genRandomConstants();
    choiceList = [];
    choiceList.addAll(terminalNames);
    choiceList.addAll(constantNames);
    functions.forEach((fw) {
      for (var i = 0; i < fw.weight; i++) {
        choiceList.add(fw.symbol);
      }
    });
    var choices = List.generate<int>(totalWeight, (index) => index);
    choices.shuffle();

    // head is made up of any symbol (function, input, or constant).
    var headList = List.generate<Symbol>(
        headSize, (index) => choiceList[choices[index % choices.length]]);
    // tail is strictly made up of terminals (input or constant).
    var tailList = List.generate<Symbol>(tailSize,
        (index) => choiceList[choices[index % choices.length] % numTerminals]);
    symbols = [];
    symbols.addAll(headList);
    symbols.addAll(tailList);

    // var ao = argOrder();
    // model = buildModel(0, ao);
  }

  final Map<Symbol, Func<T>> allFuncs;
  List<Symbol> symbols;
  List<T> constants;
  FuncImpl<T> model;

  @visibleForTesting
  int headSize;
  @visibleForTesting
  int numTerminals;
  @visibleForTesting
  int numConstants;
  @visibleForTesting
  List<Symbol> choiceList;

  // Note that symbolMap does not represent the total number
  // of times each symbol appears in the list, but the total
  // number of times each symbol appears in the a actual
  // evaluation expression.
  @visibleForTesting
  Map<Symbol, int> symbolMap;

  T get zeroValue => null;

  // toString returns the Karva representation of the Gene.
  String toString() {
    var syms =
        List.generate(symbols.length, (i) => MirrorSystem.getName(symbols[i]));
    return syms.join('.');
  }

  // mutate mutates a [Gene] by performing a single random symbol exchange within
  // the [Gene].
  mutate() {
    var position = Random().nextInt(symbols.length);
    if (numTerminals < 2) {
      // Force choice to be within the head.
      position %= headSize;
    }
    // TODO: Finish this.
    if (position < headSize) {
    } else {
      // Must choose strictly from terminals.
    }
  }

  // argOrder generates a slice of argument indices (1-based) for every function
  // within the list of symbols. It takes into account the arity of each function.
  //
  // argOrder is used to build up the actual evaluatable expression tree.
  //
  // For example:
  //   '+.*.-./' => [[1, 2], [3, 4], [5, 6], [7, 8]]
  //   '+.d0.c0./' => [[1, 2], nil, nil, [3, 4]]
  @visibleForTesting
  List<List<int>> argOrder() {
    List<List<int>> result = [];
    var argCount = 0;
    symbols.forEach((sym) {
      if (!allFuncs.containsKey(sym)) {
        result.add(null);
        return;
      }
      final f = allFuncs[sym];
      final n = f.terminals;
      if (n <= 0) {
        return;
      }
      result.add(List.generate(n, (i) => ++argCount));
    });
    return result;
  }

  // buildModel recursively builds a function that implements the Karva
  // expression. While it build, it also builds up the actual symbol
  // usage within [symbolMap].
  @visibleForTesting
  buildModel(int symbolIndex, List<List<int>> argOrder) {
    if (symbolIndex >= symbols.length) {
      throw 'bad symbolIndex $symbolIndex for symbols $symbols';
    }
    var sym = symbols[symbolIndex];
    symbolMap[sym] ??= 0;
    symbolMap[sym]++;
    if (allFuncs.containsKey(sym)) {
      var f = allFuncs[sym];
      var args = argOrder[symbolIndex];
      var funcs = List.generate(
          args.length, (index) => buildModel(args[index], argOrder));
      return (List<T> input) {
        var values =
            List.generate<T>(funcs.length, (index) => funcs[index](input));
        return f.func(values);
      };
    } else {
      var symName = MirrorSystem.getName(sym);
      if (symName.startsWith('d')) {
        // No named symbol found - look for inputs and constants
        var index = int.tryParse(symName.substring(1));
        if (index == null) {
          throw 'unable to parse input index: sym=$symName';
        }
        return (List<T> input) {
          if (index >= input.length) {
            print(
                'error evaluating gene $sym: index $index >= d length (${input.length})');
            return 0.0;
          }
          return input[index];
        };
      } else if (symName.startsWith('c')) {
        var index = int.tryParse(symName.substring(1));
        if (index == null) {
          throw 'unable to parse constant index: sym=$symName';
        }
        return (List<T> input) {
          if (index >= constants.length) {
            print(
                'error evaluating gene $sym: index $index >= c length (${input.length})');
            return 0.0;
          }
          return constants[index];
        };
      }
    }
    throw 'unable to return function: unknown gene symbol $sym';
  }
}

class BoolGene extends Gene<bool> {
  BoolGene(Map<Symbol, Func<bool>> allFuncs) : super(allFuncs);

  BoolGene.fromKarva(String karva, Map<Symbol, Func<bool>> allFuncs)
      : super.fromKarva(karva, allFuncs);

  BoolGene.random({
    int headSize = 7,
    int numTerminals,
    int numConstants = 5,
    List<WeightedSymbol> functions,
    Map<Symbol, Func<bool>> allFuncs,
  }) : super.random(headSize, numTerminals, numConstants, functions,
            allFuncs ?? boolNandNodes);

  @override
  genRandomConstants() {
    // Override this.
    constants =
        List.generate<bool>(numConstants, (index) => Random().nextBool());
  }

  @override
  bool get zeroValue => false;
}

class DoubleGene extends Gene<double> {
  DoubleGene(Map<Symbol, Func<double>> allFuncs) : super(allFuncs);

  DoubleGene.fromKarva(String karva, Map<Symbol, Func<double>> allFuncs)
      : super.fromKarva(karva, allFuncs);

  DoubleGene.random({
    int headSize = 7,
    int numTerminals,
    int numConstants = 5,
    List<WeightedSymbol> functions,
    Map<Symbol, Func<double>> allFuncs,
  }) : super.random(headSize, numTerminals, numConstants, functions,
            allFuncs ?? allDoubleNodes);

  @override
  genRandomConstants() {
    // Override this.
    constants =
        List.generate<double>(numConstants, (index) => Random().nextDouble());
  }

  @override
  double get zeroValue => 0.0;
}

class IntGene extends Gene<int> {
  IntGene(Map<Symbol, Func<int>> allFuncs) : super(allFuncs);

  IntGene.fromKarva(String karva, Map<Symbol, Func<int>> allFuncs)
      : super.fromKarva(karva, allFuncs);

  IntGene.random({
    int headSize = 7,
    int numTerminals,
    int numConstants = 5,
    List<WeightedSymbol> functions,
    Map<Symbol, Func<int>> allFuncs,
  }) : super.random(headSize, numTerminals, numConstants, functions,
            allFuncs ?? allIntNodes);

  @override
  genRandomConstants() {
    // Override this.
    constants = List.generate<int>(
        numConstants, (index) => Random().nextInt(1000) - 500);
  }

  @override
  int get zeroValue => 0;
}

class VectorBoolGene extends Gene<VectorBool> {
  VectorBoolGene(Map<Symbol, Func<VectorBool>> allFuncs) : super(allFuncs);

  VectorBoolGene.fromKarva(String karva, Map<Symbol, Func<VectorBool>> allFuncs)
      : super.fromKarva(karva, allFuncs);

  VectorBoolGene.random({
    int headSize = 7,
    int numTerminals,
    int numConstants = 5,
    List<WeightedSymbol> functions,
    Map<Symbol, Func<VectorBool>> allFuncs,
  }) : super.random(headSize, numTerminals, numConstants, functions,
            allFuncs ?? vectorBoolNandNodes);

  // TODO: @override genRandomConstants();

  @override
  VectorBool get zeroValue => VectorBool([]);
}

class VectorDoubleGene extends Gene<VectorDouble> {
  VectorDoubleGene(Map<Symbol, Func<VectorDouble>> allFuncs) : super(allFuncs);

  VectorDoubleGene.fromKarva(
      String karva, Map<Symbol, Func<VectorDouble>> allFuncs)
      : super.fromKarva(karva, allFuncs);

  VectorDoubleGene.random({
    int headSize = 7,
    int numTerminals,
    int numConstants = 5,
    List<WeightedSymbol> functions,
    Map<Symbol, Func<VectorDouble>> allFuncs,
  }) : super.random(headSize, numTerminals, numConstants, functions,
            allFuncs ?? allVectorDoubleNodes);

  // TODO: @override genRandomConstants();

  @override
  VectorDouble get zeroValue => VectorDouble([]);
}

class VectorIntGene extends Gene<VectorInt> {
  VectorIntGene(Map<Symbol, Func<VectorInt>> allFuncs) : super(allFuncs);

  VectorIntGene.fromKarva(String karva, Map<Symbol, Func<VectorInt>> allFuncs)
      : super.fromKarva(karva, allFuncs);

  VectorIntGene.random({
    int headSize = 7,
    int numTerminals,
    int numConstants = 5,
    List<WeightedSymbol> functions,
    Map<Symbol, Func<VectorInt>> allFuncs,
  }) : super.random(headSize, numTerminals, numConstants, functions,
            allFuncs ?? allVectorIntNodes);

  // TODO: @override genRandomConstants();

  @override
  VectorInt get zeroValue => VectorInt([]);
}
