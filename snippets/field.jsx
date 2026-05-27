export const Field = ({ name, type, required, recommended }) => {
  const label = required ? 'required' : recommended ? 'recommended' : null;
  const typeLabel = typeof type === 'string' ? type : null;
  const ariaParts = [name, typeLabel && `${typeLabel}`, label].filter(Boolean);

  return (
    <span
      aria-label={ariaParts.join(', ')}
      className={label ? 'field-wrap has-field-tip' : 'field-wrap'}
      style={{ position: 'relative', cursor: label ? 'default' : undefined }}
      tabIndex={label ? 0 : undefined}
    >
      <span className="field-name-row">
        <code>{name}</code>
        {required && <span className="field-req"> *</span>}
        {recommended && <span className="field-rec"> ●</span>}
      </span>
      {type && <span className="field-type">{type}</span>}
      {label && (
        <span className="field-tip" role="tooltip">
          {label}
        </span>
      )}
    </span>
  );
};
