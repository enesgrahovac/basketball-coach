# Basketball Shot Analysis - Evaluation Framework

A comprehensive evaluation system for testing and comparing different AI models and prompts for basketball shot analysis.

## Overview

This framework helps you:

- **Compare Models**: Test different Gemini models (Flash, Pro, etc.) and configurations
- **Optimize Prompts**: Evaluate different prompt formulations for better accuracy
- **Measure Performance**: Track accuracy, latency, cost, and reliability metrics
- **Analyze Errors**: Deep dive into misclassifications and model failures
- **Ground Truth**: Use user-corrected analysis as the gold standard

## Quick Start

1. **Install Dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

2. **Configure Environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your API keys and Supabase credentials
   ```

3. **Sync Data** (downloads videos and prepares ground truth):
   ```bash
   jupyter notebook notebooks/1_data_sync.ipynb
   ```

4. **Run Evaluation**:
   ```bash
   jupyter notebook notebooks/2_model_comparison.ipynb
   ```

## Key Features

### 🎯 Model Evaluation
- Test multiple Gemini model variants
- Compare different prompt formulations
- Measure accuracy on shot type and make/miss classification
- Track inference latency and API costs

### 📊 Performance Metrics
- **Shot Type Accuracy**: Lay-up, mid-range, three-pointer, etc.
- **Make/Miss Accuracy**: Binary classification performance
- **Combined Accuracy**: Both classifications correct
- **Parse Success Rate**: JSON output reliability
- **Cost Analysis**: API usage and pricing
- **Speed Analysis**: Inference time per sample

### 🔍 Error Analysis
- Confusion matrices for detailed error patterns
- Individual error case analysis
- Confidence calibration assessment
- Parse failure investigation

### 📈 Visualization
- Interactive performance dashboards
- Speed vs accuracy trade-off charts
- Cost-effectiveness analysis
- Error pattern visualization

## Data Flow

1. **Supabase Sync**: Fetch clips, analysis, and user corrections
2. **Video Download**: Cache videos locally for evaluation
3. **Ground Truth**: Build dataset using user-corrected labels
4. **Model Testing**: Run inference on test samples
5. **Metrics**: Calculate performance statistics
6. **Analysis**: Generate insights and recommendations

## Configuration

### Models (`configs/models.yaml`)
```yaml
models:
  gemini_flash:
    name: "models/gemini-2.5-flash"
    description: "Fast, cost-effective model"
  gemini_pro:
    name: "models/gemini-2.5-pro"
    description: "High-quality, more expensive model"
```

### Prompts (`configs/prompts.yaml`)
```yaml
prompts:
  current_production:
    name: "Current Production Prompt"
    content: "Your detailed prompt here..."
  simplified:
    name: "Simplified Prompt"
    content: "Simpler prompt variation..."
```

## Usage Examples

### Basic Evaluation
```python
from src.evaluator import ModelEvaluator
from src.data_manager import EvaluationDataManager

# Load ground truth data
data_manager = EvaluationDataManager(supabase_url, supabase_key)
ground_truth = data_manager.load_ground_truth()

# Run evaluation
evaluator = ModelEvaluator(gemini_api_key)
results = evaluator.evaluate_model(
    model_name="models/gemini-2.5-flash",
    prompt=your_prompt,
    ground_truth_data=ground_truth
)
```

### Batch Comparison
```python
# Test multiple model/prompt combinations
models = ['gemini_flash', 'gemini_pro']
prompts = ['current_production', 'simplified']

for model in models:
    for prompt in prompts:
        results = evaluator.evaluate_model(...)
        # Analyze results
```

## Results Structure

Evaluation results are saved in `data/model_outputs/` with this structure:

```
model_outputs/
├── gemini-2.5-flash/
│   ├── eval_1234567890_fps24_medium.json
│   └── eval_1234567891_fps30_high.json
└── gemini-2.5-pro/
    └── eval_1234567892_fps24_medium.json
```

Each result file contains:
- Model configuration
- Performance metrics
- Individual predictions
- Error analysis
- Cost and timing data

## Best Practices

### Data Management
- Run data sync regularly to get latest corrections
- Keep videos cached locally to avoid re-downloading
- Monitor dataset balance (shot types, make/miss ratio)

### Evaluation Strategy
- Start with small samples (TEST_MODE=True) for quick testing
- Use full dataset for final model selection
- Test multiple prompt variations systematically
- Consider different video processing settings

### Model Selection
- Balance accuracy, speed, and cost for your use case
- Consider confidence calibration for user experience
- Test edge cases and failure modes
- Validate on held-out test set

## Troubleshooting

### Common Issues

**Missing Ground Truth Data**:
```bash
# Run data sync notebook first
jupyter notebook notebooks/1_data_sync.ipynb
```

**API Key Errors**:
```bash
# Check .env file has correct keys
cat .env | grep API_KEY
```

**Video Download Failures**:
- Check Supabase storage permissions
- Verify bucket name in configuration
- Ensure videos exist in storage

**Parse Failures**:
- Check prompt formatting
- Verify JSON schema expectations
- Review model output in results

## Contributing

To add new models or metrics:

1. Update configuration files in `configs/`
2. Extend evaluator classes in `src/`
3. Add new visualization in `metrics.py`
4. Update notebooks with new options
5. Test thoroughly and document changes

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review notebook outputs for error details
3. Examine saved results in `data/model_outputs/`
4. Check Supabase connectivity and permissions
