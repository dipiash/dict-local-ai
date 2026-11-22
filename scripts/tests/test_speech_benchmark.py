import importlib.util
import json
import pathlib
import unittest

PATH = pathlib.Path(__file__).resolve().parents[1] / 'evaluation' / 'score.py'
spec = importlib.util.spec_from_file_location('speech_score', PATH)
score = importlib.util.module_from_spec(spec)
spec.loader.exec_module(score)
try:
    import pyannote.metrics  # optional: evaluator is not needed by the app itself
    HAS_DIARIZATION_METRICS = True
except ImportError:
    HAS_DIARIZATION_METRICS = False


class SpeechBenchmarkTests(unittest.TestCase):
    def test_reference_cases_are_not_fabricated(self):
        cases = json.loads((PATH.parents[2] / 'benchmarks' / 'references.json').read_text())
        self.assertEqual(len(cases['cases']), 1)
        self.assertTrue(all(not x['verified'] for x in cases['cases']))
        self.assertTrue(all(not x['speaker_turns'] and not x['reference_text'] for x in cases['cases']))

    def test_wer_counts(self):
        item = score.word_edits('The quick brown fox', 'the slow brown fox')
        self.assertEqual(item['sub'], 1)
        self.assertEqual(item['hits'], 3)
        self.assertAlmostEqual(item['wer'], .25)
        self.assertEqual(score.word_edits('one two three', 'one three')['del'], 1)
        self.assertEqual(score.word_edits('one two', 'one other two')['ins'], 1)

    def test_unreviewed_never_used(self):
        case = {'id': 'x', 'verified': False}
        self.assertFalse(score.validate_case(case))
        case.update(verified=True, start=0, end=10, reference_text='', speaker_turns=[])
        with self.assertRaises(ValueError):
            score.validate_case(case)

    @unittest.skipUnless(HAS_DIARIZATION_METRICS, "optional pyannote.metrics not installed")
    def test_global_mapping_detects_identity_collapse_across_windows(self):
        ref = {'cases': [
            dict(id='first', recording='pg', start=0, end=5, verified=True,
                reference_text='hello', speaker_turns=[dict(start=0,end=5,speaker='person_A')]),
            dict(id='second', recording='pg', start=6, end=11, verified=True,
                reference_text='world', speaker_turns=[dict(start=6,end=11,speaker='person_B')]),
        ]}
        aud = {'pg': {'duration':12, 'method':'nemotron3-fast128',
            'rawTurns':[dict(start=0,end=5,id='S1'),dict(start=6,end=11,id='S1')],
            'words':[dict(start=1,end=2,text='hello'),dict(start=7,end=8,text='world')]}}
        result = score.score(ref,aud)
        self.assertTrue(all(c['der'] == 0 for c in result['cases']))
        self.assertAlmostEqual(result['der'], 0.5)

    @unittest.skipUnless(HAS_DIARIZATION_METRICS, "optional pyannote.metrics not installed")
    def test_scoring_known_perfect_diarization(self):
        ref = {'cases': [dict(id='x', recording='pg', start=0, end=5,
            verified=True, reference_text='Hello world',
            speaker_turns=[dict(start=0,end=5,speaker='person')])]}
        aud = {'pg': {'duration':10, 'method':'nemotron3-fast128',
            'rawTurns':[dict(start=0,end=5,id='S4')],
            'words':[dict(start=0,end=0.5,text='hello'),dict(start=1,end=2,text='world')]}}
        result = score.score(ref,aud)
        self.assertAlmostEqual(result['wer'],0.0)
        self.assertAlmostEqual(result['der'],0.0)


if __name__ == '__main__': unittest.main()
