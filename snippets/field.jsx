export const Field = ({ name, type, required, recommended }) => {
  const [show, setShow] = useState(false);

  const label = required ? 'required' : recommended ? 'recommended' : null;

  return (
    <span
      onMouseEnter={() => label && setShow(true)}
      onMouseLeave={() => setShow(false)}
      style={{ position: 'relative', cursor: label ? 'default' : undefined }}
    >
      <code>{name}</code>
      {required && <span className="field-req"> *</span>}
      {recommended && <span className="field-rec"> ●</span>}
      {type && <><br />({type})</>}
      {show && (
        <span
          style={{
            position: 'absolute',
            bottom: 'calc(100% + 4px)',
            left: 0,
            zIndex: 50,
            padding: '2px 8px',
            borderRadius: '4px',
            fontSize: '0.7rem',
            fontWeight: 500,
            whiteSpace: 'nowrap',
            backgroundColor: '#1f2937',
            color: '#e5e7eb',
            border: '1px solid rgba(255,255,255,0.1)',
            boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
            pointerEvents: 'none',
          }}
        >
          {label}
        </span>
      )}
    </span>
  );
};
