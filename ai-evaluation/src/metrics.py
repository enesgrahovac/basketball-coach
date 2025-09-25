"""
Metrics and visualization utilities for basketball shot analysis evaluation.
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from typing import Dict, List, Any, Optional
from pathlib import Path
import json
from sklearn.metrics import confusion_matrix, classification_report
import plotly.graph_objects as go
import plotly.express as px
from plotly.subplots import make_subplots


class EvaluationMetrics:
    """Comprehensive metrics calculation and visualization for model evaluation."""
    
    def __init__(self):
        """Initialize metrics calculator."""
        self.shot_types = ['lay_up', 'in_paint', 'mid_range', 'three_pointer', 'free_throw']
        self.results = ['make', 'miss']
    
    def load_evaluation_results(self, results_dir: str) -> Dict[str, List[Dict]]:
        """Load all evaluation results from directory."""
        results_path = Path(results_dir)
        all_results = {}
        
        for model_dir in results_path.iterdir():
            if model_dir.is_dir():
                model_name = model_dir.name
                all_results[model_name] = []
                
                for result_file in model_dir.glob("*.json"):
                    with open(result_file, 'r') as f:
                        data = json.load(f)
                        all_results[model_name].append(data)
        
        return all_results
    
    def create_comparison_dataframe(self, all_results: Dict[str, List[Dict]]) -> pd.DataFrame:
        """Create a DataFrame comparing all model evaluations."""
        comparison_data = []
        
        for model_name, evaluations in all_results.items():
            for eval_data in evaluations:
                metrics = eval_data['metrics']
                config = eval_data['configuration']
                
                row = {
                    'model_name': model_name,
                    'fps': config.get('fps', 24),
                    'media_resolution': config.get('media_resolution', 'MEDIUM'),
                    'total_samples': metrics.get('total_samples', 0),
                    'valid_predictions': metrics.get('valid_predictions', 0),
                    'parse_success_rate': metrics.get('parse_success_rate', 0),
                    'shot_type_accuracy': metrics.get('shot_type_accuracy', 0),
                    'result_accuracy': metrics.get('result_accuracy', 0),
                    'both_correct_accuracy': metrics.get('both_correct_accuracy', 0),
                    'average_confidence': metrics.get('average_confidence', 0),
                    'average_inference_time': np.mean([r['inference_time_s'] for r in eval_data['results']]),
                    'total_cost': sum([r['cost_usd'] for r in eval_data['results']]),
                    'cost_per_sample': sum([r['cost_usd'] for r in eval_data['results']]) / len(eval_data['results']) if eval_data['results'] else 0,
                    'evaluation_timestamp': eval_data['evaluation_timestamp']
                }
                comparison_data.append(row)
        
        return pd.DataFrame(comparison_data)
    
    def plot_model_comparison(self, df: pd.DataFrame) -> go.Figure:
        """Create interactive comparison plot of model performance."""
        
        fig = make_subplots(
            rows=2, cols=2,
            subplot_titles=('Accuracy Comparison', 'Speed vs Accuracy', 'Cost Analysis', 'Confidence Calibration'),
            specs=[[{"secondary_y": False}, {"secondary_y": False}],
                   [{"secondary_y": True}, {"secondary_y": False}]]
        )
        
        # Accuracy comparison
        fig.add_trace(
            go.Bar(
                x=df['model_name'],
                y=df['shot_type_accuracy'],
                name='Shot Type Accuracy',
                marker_color='lightblue'
            ),
            row=1, col=1
        )
        
        fig.add_trace(
            go.Bar(
                x=df['model_name'],
                y=df['result_accuracy'],
                name='Make/Miss Accuracy',
                marker_color='lightcoral'
            ),
            row=1, col=1
        )
        
        # Speed vs Accuracy scatter
        fig.add_trace(
            go.Scatter(
                x=df['average_inference_time'],
                y=df['both_correct_accuracy'],
                mode='markers+text',
                text=df['model_name'],
                textposition="top center",
                name='Speed vs Accuracy',
                marker=dict(size=10, color='green')
            ),
            row=1, col=2
        )
        
        # Cost analysis
        fig.add_trace(
            go.Bar(
                x=df['model_name'],
                y=df['cost_per_sample'],
                name='Cost per Sample',
                marker_color='gold'
            ),
            row=2, col=1
        )
        
        # Add accuracy as secondary y-axis for cost plot
        fig.add_trace(
            go.Scatter(
                x=df['model_name'],
                y=df['both_correct_accuracy'],
                mode='markers+lines',
                name='Accuracy',
                marker=dict(color='red', size=8),
                yaxis='y4'
            ),
            row=2, col=1
        )
        
        # Confidence vs Accuracy
        fig.add_trace(
            go.Scatter(
                x=df['average_confidence'],
                y=df['both_correct_accuracy'],
                mode='markers+text',
                text=df['model_name'],
                textposition="top center",
                name='Confidence Calibration',
                marker=dict(size=10, color='purple')
            ),
            row=2, col=2
        )
        
        # Update layout
        fig.update_layout(
            height=800,
            title_text="Model Performance Comparison Dashboard",
            showlegend=True
        )
        
        # Update x and y axis labels
        fig.update_xaxes(title_text="Model", row=1, col=1)
        fig.update_yaxes(title_text="Accuracy", row=1, col=1)
        
        fig.update_xaxes(title_text="Inference Time (s)", row=1, col=2)
        fig.update_yaxes(title_text="Both Correct Accuracy", row=1, col=2)
        
        fig.update_xaxes(title_text="Model", row=2, col=1)
        fig.update_yaxes(title_text="Cost per Sample ($)", row=2, col=1)
        fig.update_yaxes(title_text="Accuracy", secondary_y=True, row=2, col=1)
        
        fig.update_xaxes(title_text="Average Confidence", row=2, col=2)
        fig.update_yaxes(title_text="Both Correct Accuracy", row=2, col=2)
        
        return fig
    
    def plot_confusion_matrices(self, eval_data: Dict) -> go.Figure:
        """Create confusion matrices for shot type and result classification."""
        
        metrics = eval_data['metrics']
        
        # Extract confusion matrices
        shot_type_cm = metrics.get('shot_type_confusion_matrix', {})
        result_cm = metrics.get('result_confusion_matrix', {})
        
        fig = make_subplots(
            rows=1, cols=2,
            subplot_titles=('Shot Type Confusion Matrix', 'Make/Miss Confusion Matrix'),
            specs=[[{"type": "heatmap"}, {"type": "heatmap"}]]
        )
        
        # Shot type confusion matrix
        if shot_type_cm:
            st_matrix, st_labels = self._build_confusion_matrix(shot_type_cm, self.shot_types)
            
            fig.add_trace(
                go.Heatmap(
                    z=st_matrix,
                    x=st_labels,
                    y=st_labels,
                    colorscale='Blues',
                    showscale=True,
                    text=st_matrix,
                    texttemplate="%{text}",
                    textfont={"size": 12}
                ),
                row=1, col=1
            )
        
        # Result confusion matrix
        if result_cm:
            r_matrix, r_labels = self._build_confusion_matrix(result_cm, self.results)
            
            fig.add_trace(
                go.Heatmap(
                    z=r_matrix,
                    x=r_labels,
                    y=r_labels,
                    colorscale='Reds',
                    showscale=True,
                    text=r_matrix,
                    texttemplate="%{text}",
                    textfont={"size": 12}
                ),
                row=1, col=2
            )
        
        fig.update_layout(
            title_text=f"Confusion Matrices - {eval_data['model_name']}",
            height=400
        )
        
        return fig
    
    def _build_confusion_matrix(self, confusion_dict: Dict[str, int], labels: List[str]) -> tuple:
        """Build confusion matrix from dictionary format."""
        matrix = np.zeros((len(labels), len(labels)), dtype=int)
        
        for transition, count in confusion_dict.items():
            if " -> " in transition:
                true_label, pred_label = transition.split(" -> ")
                if true_label in labels and pred_label in labels:
                    true_idx = labels.index(true_label)
                    pred_idx = labels.index(pred_label)
                    matrix[true_idx][pred_idx] = count
        
        return matrix, labels
    
    def generate_error_analysis(self, eval_data: Dict) -> pd.DataFrame:
        """Generate detailed error analysis from evaluation results."""
        results = eval_data['results']
        errors = []
        
        for result in results:
            gt = result['ground_truth']
            pred = result['prediction']
            
            # Skip successful predictions
            gt_shot_type = gt['shot_type']
            gt_result = gt['result']
            pred_shot_type = self._normalize_shot_type(pred.get('range'))
            pred_result = self._normalize_result(pred.get('make_miss'))
            
            shot_type_correct = gt_shot_type == pred_shot_type
            result_correct = gt_result == pred_result
            
            if not (shot_type_correct and result_correct):
                error = {
                    'clip_id': result['clip_id'],
                    'gt_shot_type': gt_shot_type,
                    'pred_shot_type': pred_shot_type,
                    'shot_type_error': not shot_type_correct,
                    'gt_result': gt_result,
                    'pred_result': pred_result,
                    'result_error': not result_correct,
                    'confidence': pred.get('confidence', 0),
                    'inference_time': result['inference_time_s'],
                    'has_parse_error': 'error' in pred
                }
                errors.append(error)
        
        return pd.DataFrame(errors)
    
    def _normalize_shot_type(self, shot_type: Optional[str]) -> Optional[str]:
        """Normalize shot type to match database format."""
        if not shot_type:
            return None
        
        mapping = {
            "LAY_UP": "lay_up",
            "IN_PAINT": "in_paint", 
            "MID_RANGE": "mid_range",
            "THREE_POINTER": "three_pointer",
            "FREE_THROW": "free_throw"
        }
        
        return mapping.get(shot_type.upper(), shot_type.lower())
    
    def _normalize_result(self, result: Optional[str]) -> Optional[str]:
        """Normalize make/miss result to match database format."""
        if not result:
            return None
        
        result_upper = result.upper()
        if result_upper == "MAKE":
            return "make"
        elif result_upper == "MISS":
            return "miss"
        
        return None
    
    def create_performance_summary(self, comparison_df: pd.DataFrame) -> str:
        """Generate a text summary of model performance."""
        
        summary = "# Basketball Shot Analysis - Model Performance Summary\n\n"
        
        # Best performing models
        best_accuracy = comparison_df.loc[comparison_df['both_correct_accuracy'].idxmax()]
        fastest = comparison_df.loc[comparison_df['average_inference_time'].idxmin()]
        cheapest = comparison_df.loc[comparison_df['cost_per_sample'].idxmin()]
        
        summary += f"## Top Performers\n\n"
        summary += f"**Highest Accuracy:** {best_accuracy['model_name']} ({best_accuracy['both_correct_accuracy']:.3f})\n"
        summary += f"**Fastest:** {fastest['model_name']} ({fastest['average_inference_time']:.2f}s)\n"
        summary += f"**Most Cost-Effective:** {cheapest['model_name']} (${cheapest['cost_per_sample']:.4f} per sample)\n\n"
        
        # Overall statistics
        summary += f"## Dataset Statistics\n\n"
        summary += f"**Total Samples:** {comparison_df['total_samples'].iloc[0]}\n"
        summary += f"**Models Evaluated:** {len(comparison_df)}\n"
        summary += f"**Average Parse Success Rate:** {comparison_df['parse_success_rate'].mean():.3f}\n\n"
        
        # Accuracy breakdown
        summary += f"## Accuracy Analysis\n\n"
        summary += f"**Shot Type Classification:**\n"
        summary += f"- Best: {comparison_df['shot_type_accuracy'].max():.3f}\n"
        summary += f"- Worst: {comparison_df['shot_type_accuracy'].min():.3f}\n"
        summary += f"- Average: {comparison_df['shot_type_accuracy'].mean():.3f}\n\n"
        
        summary += f"**Make/Miss Classification:**\n"
        summary += f"- Best: {comparison_df['result_accuracy'].max():.3f}\n"
        summary += f"- Worst: {comparison_df['result_accuracy'].min():.3f}\n"
        summary += f"- Average: {comparison_df['result_accuracy'].mean():.3f}\n\n"
        
        # Cost and speed analysis
        summary += f"## Performance Analysis\n\n"
        summary += f"**Inference Time:**\n"
        summary += f"- Fastest: {comparison_df['average_inference_time'].min():.2f}s\n"
        summary += f"- Slowest: {comparison_df['average_inference_time'].max():.2f}s\n"
        summary += f"- Average: {comparison_df['average_inference_time'].mean():.2f}s\n\n"
        
        summary += f"**Cost per Sample:**\n"
        summary += f"- Cheapest: ${comparison_df['cost_per_sample'].min():.4f}\n"
        summary += f"- Most Expensive: ${comparison_df['cost_per_sample'].max():.4f}\n"
        summary += f"- Average: ${comparison_df['cost_per_sample'].mean():.4f}\n\n"
        
        return summary
