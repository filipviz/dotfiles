#!/bin/sh
input=$(cat)

time_str=$(date +%H:%M:%S)
cwd=$(echo "$input" | jq -r '.cwd')
model=$(echo "$input" | jq -r '.model.display_name')

# Abbreviate home directory to ~
home_dir="$HOME"
case "$cwd" in
    "$home_dir"*)
        display_cwd="~${cwd#$home_dir}"
        ;;
    *)
        display_cwd="$cwd"
        ;;
esac

# Get git branch, skipping optional locks to avoid blocking
branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)

# Reasoning effort: prefer live input field, fall back to settings.json
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -z "$effort" ]; then
    effort=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
fi

# Context window usage (pre-calculated percentage, degrades gracefully)
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$ctx_used" ]; then
    ctx_str=$(printf "ctx:%.0f%%" "$ctx_used")
else
    ctx_str=""
fi

# Rate limits: 5-hour session and 7-day weekly (only shown when present)
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rate_str=""
if [ -n "$five_pct" ]; then
    rate_str=$(printf "5h:%.0f%%" "$five_pct")
fi
if [ -n "$week_pct" ]; then
    week_part=$(printf "7d:%.0f%%" "$week_pct")
    if [ -n "$rate_str" ]; then
        rate_str="$rate_str $week_part"
    else
        rate_str="$week_part"
    fi
fi

# Build model+effort label
if [ -n "$effort" ]; then
    model_label="$model [$effort]"
else
    model_label="$model"
fi

# Build the suffix (context / rate limits), dimmed yellow
suffix=""
if [ -n "$ctx_str" ] && [ -n "$rate_str" ]; then
    suffix="$ctx_str $rate_str"
elif [ -n "$ctx_str" ]; then
    suffix="$ctx_str"
elif [ -n "$rate_str" ]; then
    suffix="$rate_str"
fi

# Green for time, blue for cwd, red for git branch, yellow for usage stats
if [ -n "$branch" ]; then
    printf '\033[32m%s\033[0m \033[34m%s\033[0m \033[31m%s\033[0m %s' \
        "$time_str" "$display_cwd" "$branch" "$model_label"
else
    printf '\033[32m%s\033[0m \033[34m%s\033[0m %s' \
        "$time_str" "$display_cwd" "$model_label"
fi

if [ -n "$suffix" ]; then
    printf ' \033[33m%s\033[0m' "$suffix"
fi
