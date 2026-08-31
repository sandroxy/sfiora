function invariant(condition, message) {
  if (!condition) {
    throw new Error(`Contract check failed: ${message}`);
  }
}

function schemaErrors(value, definition, path, rootSchema) {
  if (definition.$ref) {
    const prefix = '#/$defs/';
    invariant(
      definition.$ref.startsWith(prefix),
      `unsupported schema reference: ${definition.$ref}`
    );
    const referencedDefinition =
      rootSchema.$defs[definition.$ref.slice(prefix.length)];
    invariant(
      referencedDefinition,
      `missing schema reference: ${definition.$ref}`
    );
    return schemaErrors(value, referencedDefinition, path, rootSchema);
  }

  if (definition.oneOf) {
    const matchCount = definition.oneOf.filter(
      (candidate) =>
        schemaErrors(value, candidate, path, rootSchema).length === 0
    ).length;
    return matchCount === 1
      ? []
      : [`${path} must match exactly one declared schema`];
  }

  if (definition.anyOf) {
    const matches = definition.anyOf.some(
      (candidate) =>
        schemaErrors(value, candidate, path, rootSchema).length === 0
    );
    return matches ? [] : [`${path} must match a declared schema`];
  }

  const errors = [];
  if (
    Object.hasOwn(definition, 'const') &&
    JSON.stringify(value) !== JSON.stringify(definition.const)
  ) {
    errors.push(`${path} must equal ${JSON.stringify(definition.const)}`);
  }
  if (
    definition.enum &&
    !definition.enum.some(
      (candidate) => JSON.stringify(value) === JSON.stringify(candidate)
    )
  ) {
    errors.push(`${path} contains an undeclared enum value`);
  }

  switch (definition.type) {
    case 'object': {
      if (!value || typeof value !== 'object' || Array.isArray(value)) {
        errors.push(`${path} must be an object`);
        break;
      }
      for (const required of definition.required || []) {
        if (!Object.hasOwn(value, required)) {
          errors.push(`${path}.${required} is required`);
        }
      }
      const properties = definition.properties || {};
      for (const [key, childValue] of Object.entries(value)) {
        if (Object.hasOwn(properties, key)) {
          errors.push(
            ...schemaErrors(
              childValue,
              properties[key],
              `${path}.${key}`,
              rootSchema
            )
          );
        } else if (definition.additionalProperties === false) {
          errors.push(`${path}.${key} is not declared`);
        } else if (
          definition.additionalProperties &&
          typeof definition.additionalProperties === 'object'
        ) {
          errors.push(
            ...schemaErrors(
              childValue,
              definition.additionalProperties,
              `${path}.${key}`,
              rootSchema
            )
          );
        }
      }
      break;
    }
    case 'array': {
      if (!Array.isArray(value)) {
        errors.push(`${path} must be an array`);
        break;
      }
      if (
        Number.isInteger(definition.minItems) &&
        value.length < definition.minItems
      ) {
        errors.push(`${path} contains too few items`);
      }
      if (
        definition.uniqueItems === true &&
        new Set(value.map((item) => JSON.stringify(item))).size !==
          value.length
      ) {
        errors.push(`${path} contains duplicate items`);
      }
      if (definition.items) {
        value.forEach((item, index) => {
          errors.push(
            ...schemaErrors(
              item,
              definition.items,
              `${path}[${index}]`,
              rootSchema
            )
          );
        });
      }
      break;
    }
    case 'string':
      if (typeof value !== 'string') {
        errors.push(`${path} must be a string`);
      } else {
        if (
          Number.isInteger(definition.minLength) &&
          value.length < definition.minLength
        ) {
          errors.push(`${path} is shorter than allowed`);
        }
        if (
          definition.pattern &&
          !new RegExp(definition.pattern).test(value)
        ) {
          errors.push(`${path} does not match its declared pattern`);
        }
      }
      break;
    case 'integer':
      if (!Number.isInteger(value)) {
        errors.push(`${path} must be an integer`);
      }
      break;
    case 'number':
      if (typeof value !== 'number' || !Number.isFinite(value)) {
        errors.push(`${path} must be a finite number`);
      }
      break;
    case 'boolean':
      if (typeof value !== 'boolean') {
        errors.push(`${path} must be a boolean`);
      }
      break;
    default:
      break;
  }

  if (typeof value === 'number') {
    if (
      typeof definition.minimum === 'number' &&
      value < definition.minimum
    ) {
      errors.push(`${path} is below its declared minimum`);
    }
    if (
      typeof definition.maximum === 'number' &&
      value > definition.maximum
    ) {
      errors.push(`${path} exceeds its declared maximum`);
    }
  }
  return errors;
}

export function assertSchemaValue(
  value,
  definitionName,
  label,
  rootSchema
) {
  const definition = rootSchema.$defs[definitionName];
  invariant(definition, `JSON Schema definition ${definitionName} is missing`);
  const errors = schemaErrors(value, definition, label, rootSchema);
  invariant(
    errors.length === 0,
    `${label} does not match ${definitionName}:\n${errors.join('\n')}`
  );
}
