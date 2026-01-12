---
description: Comprehensive code review for maintainability, flexibility, and performance
---

# Code Review Guidelines

Review the following code with a focus on long-term maintainability, flexibility, and performance.

## Review Criteria

### 1. Maintainability & Code Organization
- **Single Responsibility**: Each class/module should have one clear, well-defined purpose
- **Function Length**: Functions longer than ~50 lines (one screen) should be decomposed into smaller, focused helper functions with descriptive names
- **Clear Implementation**: Logic should be straightforward and self-documenting; avoid clever tricks that sacrifice readability
- **Naming**: Classes, functions, and variables should have clear, descriptive names that reveal intent

### 2. Flexibility & Extensibility
- **Open/Closed Principle**: Code should be open for extension but closed for modification
- **Dependency Injection**: Avoid hard-coded dependencies; use interfaces or abstract classes where appropriate
- **Configuration**: Magic numbers and hardcoded values should be extracted to constants or configuration
- **API Design**: Public interfaces should be stable and well-thought-out for future compatibility

### 3. Reusability & Generalization
- **DRY Principle**: Identify and eliminate code duplication
- **Generalization**: Look for patterns that could be abstracted into reusable utilities or base classes
- **Parameterization**: Hardcoded behavior should be parameterized where it makes sense
- **Component Isolation**: Components should be loosely coupled and independently reusable

### 4. Performance Considerations
- **Move Semantics**: In C++/Rust, check for opportunities to use move semantics instead of copies (std::move, moving ownership)
- **Memory Allocations**:
  - Identify excessive heap allocations in hot paths
  - Look for unnecessary temporary object creation
  - Check for proper use of reserve() for containers with known sizes
  - Watch for allocations inside loops
- **Algorithm Complexity**: Flag O(n^2) or worse algorithms where better alternatives exist
- **Resource Management**: Ensure proper RAII, smart pointers, or equivalent resource cleanup patterns
- **Caching Opportunities**: Identify repeated expensive computations that could be cached

### 5. Code Quality Issues
- **Error Handling**: Check for proper error handling and edge cases
- **Type Safety**: Look for opportunities to use stronger typing
- **Immutability**: Prefer immutable data structures where appropriate
- **Testing**: Note whether the code is easily testable (low coupling, clear interfaces)

## Output Format

Please structure your review as follows:

**?? Critical Issues** (must fix)
- Issue description with file location and specific recommendations

**?? Improvement Opportunities** (should consider)
- Suggestions for better maintainability, flexibility, or performance

**?? Good Practices** (keep doing)
- Highlight well-written code that follows best practices

**?? Refactoring Suggestions**
- Specific proposals for decomposition, generalization, or restructuring

For each issue, provide:
1. Location (file:line or class/function name)
2. Current implementation concern
3. Why it matters (impact on maintainability/performance/flexibility)
4. Concrete suggestion for improvement with code example if helpful

Focus on actionable feedback that will make the codebase more maintainable and efficient in the long term.
